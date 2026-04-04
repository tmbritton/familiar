defmodule Familiar.Files do
  @moduledoc """
  Public API for the Files context.

  Manages atomic file operations via a SQLite-backed transaction log.
  Strict write sequence: log intent → pre-write stat check → write file → log completion.
  Provides idempotent rollback and `.fam-pending` conflict detection.

  Rollback restores tracked files via `git checkout`, deletes new files,
  and marks untracked overwrites as `skipped`.
  """

  use Boundary,
    deps: [Familiar.System.FileSystem],
    exports: [Familiar.Files, Familiar.Files.Transaction]

  require Logger

  import Ecto.Query

  alias Familiar.Files.Transaction
  alias Familiar.Repo

  @delete_sentinel "DELETE"

  # -- Write --

  @doc """
  Write a file through the transaction log.

  Strict sequence:
  1. Log intent (status: pending)
  2. Pre-write stat check — detect external modification
  3. Write file to disk via FileSystem behaviour port
  4. Log completion (status: completed)

  Returns `{:ok, transaction}` on success, `{:error, {:conflict, info}}` if
  the file was modified externally, or `{:error, reason}` on failure.
  """
  @spec write(String.t(), binary(), String.t()) :: {:ok, map()} | {:error, term()}
  def write(path, content, task_id) do
    new_hash = Transaction.content_hash(content)
    original_hash = read_current_hash(path)

    # Step 1: Log intent
    attrs = %{
      task_id: task_id,
      file_path: path,
      content_hash: new_hash,
      original_content_hash: original_hash,
      status: "pending"
    }

    with {:ok, txn} <- insert_transaction(attrs),
         # Step 2: Pre-write stat check
         :ok <- check_for_conflict(path, original_hash, content, txn),
         # Step 3: Write file
         :ok <- do_write(path, content, txn) do
      # Step 4: Log completion
      mark_completed(txn)
    end
  end

  # -- Delete --

  @doc """
  Delete a file through the transaction log.

  Reads and stores the original content hash before deleting so rollback
  can detect whether the file was modified after deletion.
  """
  @spec delete(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def delete(path, task_id) do
    original_hash = read_current_hash(path)

    attrs = %{
      task_id: task_id,
      file_path: path,
      content_hash: @delete_sentinel,
      original_content_hash: original_hash,
      status: "pending"
    }

    with {:ok, txn} <- insert_transaction(attrs),
         :ok <- check_for_conflict(path, original_hash, nil, txn),
         :ok <- do_delete(path, txn) do
      mark_completed(txn)
    end
  end

  # -- Rollback --

  @doc """
  Rollback all pending and conflict file transactions for a task.

  Idempotent: re-running on an already-rolled-back task is a no-op.
  Each file's rollback status is updated independently.
  """
  @spec rollback_task(String.t()) :: :ok
  def rollback_task(task_id) do
    rollbackable_txns(task_id)
    |> Enum.each(&safe_rollback_one/1)

    :ok
  end

  @doc """
  Rollback all pending transactions across ALL tasks.

  Called by crash recovery on startup.
  """
  @spec rollback_incomplete() :: :ok
  def rollback_incomplete do
    all_pending()
    |> Enum.each(&safe_rollback_one/1)

    :ok
  end

  # -- Queries --

  @doc """
  Return a map of `%{file_path => task_id}` for all active transactions.

  Active means status is `pending` or `conflict` (not completed, rolled_back, or skipped).
  """
  @spec claimed_files() :: map()
  def claimed_files do
    from(t in Transaction,
      where: t.status in ["pending", "conflict"],
      select: {t.file_path, t.task_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Return all transaction records with status `conflict`.
  """
  @spec pending_conflicts() :: [map()]
  def pending_conflicts do
    from(t in Transaction, where: t.status == "conflict")
    |> Repo.all()
  end

  # -- Private: Write Sequence Helpers --

  defp insert_transaction(attrs) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, txn} -> {:ok, txn}
      {:error, changeset} -> {:error, {:transaction_insert_failed, changeset}}
    end
  end

  defp check_for_conflict(path, original_hash, content, txn) do
    current_hash = read_current_hash(path)

    if original_hash != current_hash do
      handle_conflict(path, content, txn)
    else
      :ok
    end
  end

  defp handle_conflict(path, content, txn) do
    # Write agent's version as .fam-pending if we have content
    if content do
      pending_path = path <> ".fam-pending"

      case file_system().write(pending_path, content) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("[Files] Failed to write .fam-pending for #{path}: #{inspect(reason)}")
      end
    end

    update_status(txn, "conflict")
    {:error, {:conflict, %{path: path, transaction_id: txn.id}}}
  end

  defp do_write(path, content, txn) do
    case file_system().write(path, content) do
      :ok -> :ok
      {:error, reason} -> rollback_failed_write(txn, reason)
    end
  end

  defp do_delete(path, txn) do
    case file_system().delete(path) do
      :ok -> :ok
      {:error, reason} -> rollback_failed_write(txn, reason)
    end
  end

  defp rollback_failed_write(txn, reason) do
    update_status(txn, "rolled_back")
    {:error, {:file_operation_failed, reason}}
  end

  defp mark_completed(txn) do
    case Repo.update(Transaction.changeset(txn, %{status: "completed"})) do
      {:ok, _} = ok -> ok
      {:error, changeset} -> {:error, {:completion_failed, changeset.errors}}
    end
  end

  # -- Private: Rollback Helpers --

  defp rollbackable_txns(task_id) do
    from(t in Transaction,
      where: t.task_id == ^task_id and t.status in ["pending", "conflict"]
    )
    |> Repo.all()
  end

  defp all_pending do
    from(t in Transaction, where: t.status == "pending")
    |> Repo.all()
  end

  defp safe_rollback_one(txn) do
    rollback_one(txn)
  rescue
    e ->
      Logger.warning(
        "[Files] Rollback failed for #{txn.file_path} (task #{txn.task_id}): #{Exception.message(e)}"
      )
  end

  defp rollback_one(txn) do
    if txn.content_hash == @delete_sentinel do
      restore_deleted(txn)
    else
      rollback_write(txn)
    end
  end

  defp restore_deleted(txn) do
    case git_restore(txn.file_path) do
      :ok -> update_status(txn, "rolled_back")
      {:error, :not_tracked} -> update_status(txn, "skipped")
    end
  end

  defp rollback_write(txn) do
    case file_system().read(txn.file_path) do
      {:ok, current_content} ->
        current_hash = Transaction.content_hash(current_content)

        if current_hash == txn.content_hash do
          undo_write(txn)
        else
          # File was modified after our write — skip
          update_status(txn, "skipped")
        end

      {:error, {_, %{reason: :enoent}}} ->
        # File doesn't exist — nothing to clean
        update_status(txn, "rolled_back")

      {:error, reason} ->
        # Transient I/O error — don't assume file is gone
        Logger.warning("[Files] Cannot read #{txn.file_path} during rollback: #{inspect(reason)}")
        update_status(txn, "skipped")
    end
  end

  defp undo_write(txn) do
    if txn.original_content_hash do
      # File existed before our write — try git restore
      case git_restore(txn.file_path) do
        :ok -> update_status(txn, "rolled_back")
        {:error, :not_tracked} -> update_status(txn, "skipped")
      end
    else
      # New file — just delete it
      file_system().delete(txn.file_path)
      update_status(txn, "rolled_back")
    end
  end

  defp update_status(txn, status) do
    case Repo.update(Transaction.changeset(txn, %{status: status})) do
      {:ok, updated} ->
        updated

      {:error, changeset} ->
        Logger.warning(
          "[Files] Failed to update status for #{txn.file_path}: #{inspect(changeset.errors)}"
        )

        txn
    end
  end

  # -- Private: Git Helpers --

  defp git_restore(path) do
    case shell().cmd("git", ["ls-files", "--error-unmatch", path], []) do
      {:ok, %{exit_code: 0}} ->
        # File is tracked — restore from HEAD
        shell().cmd("git", ["checkout", "HEAD", "--", path], [])
        :ok

      _ ->
        {:error, :not_tracked}
    end
  end

  # -- Private: FileSystem Helpers --

  defp read_current_hash(path) do
    case file_system().read(path) do
      {:ok, content} -> Transaction.content_hash(content)
      {:error, _} -> nil
    end
  end

  defp file_system do
    Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
  end

  defp shell do
    Application.get_env(:familiar, Familiar.System.Shell, Familiar.System.RealShell)
  end
end
