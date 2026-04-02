defmodule Familiar.Knowledge.Backup do
  @moduledoc """
  Backup and restore operations for the knowledge store.

  Creates timestamped SQLite database snapshots in `.familiar/backups/`.
  Supports manual and automatic backup/restore workflows.
  """

  require Logger

  alias Familiar.Daemon.Paths

  @default_retention 10

  @doc """
  Create a backup of the knowledge store database.

  Copies `familiar.db` to `.familiar/backups/` with a timestamp filename.
  Returns the backup path and file size.

  Options:
  - `:db_path` — override database path (DI, for testing)
  - `:backups_dir` — override backups directory (DI, for testing)
  """
  @spec create(keyword()) :: {:ok, map()} | {:error, {atom(), map()}}
  def create(opts \\ []) do
    db = db_path(opts)
    dir = backups_dir(opts)

    with :ok <- ensure_dir(dir),
         :ok <- verify_source(db) do
      timestamp = format_timestamp(DateTime.utc_now())
      filename = "familiar-#{timestamp}.db"
      dest = Path.join(dir, filename)

      case File.cp(db, dest) do
        :ok ->
          {:ok, build_create_result(dest, filename, timestamp)}

        {:error, reason} ->
          {:error, {:backup_failed, %{reason: reason}}}
      end
    end
  end

  @doc """
  List available backups, newest first.

  Returns a list of maps with path, filename, size, and timestamp.

  Options:
  - `:backups_dir` — override backups directory (DI, for testing)
  """
  @spec list(keyword()) :: {:ok, [map()]}
  def list(opts \\ []) do
    dir = backups_dir(opts)

    case File.ls(dir) do
      {:ok, files} ->
        backups =
          files
          |> Enum.filter(&String.match?(&1, ~r/^familiar-.*\.db$/))
          |> Enum.map(&build_backup_info(dir, &1))
          |> Enum.sort_by(& &1.filename, :desc)

        {:ok, backups}

      {:error, _reason} ->
        {:ok, []}
    end
  end

  @doc """
  Restore the database from a backup file.

  Replaces `familiar.db` with the specified backup.

  Options:
  - `:db_path` — override database path (DI, for testing)
  """
  @spec restore(String.t(), keyword()) :: :ok | {:error, {atom(), map()}}
  def restore(backup_path, opts \\ []) do
    db = db_path(opts)

    with :ok <- verify_source(backup_path) do
      case File.cp(backup_path, db) do
        :ok ->
          Logger.info("[Backup] Database restored from #{backup_path}")
          :ok

        {:error, reason} ->
          {:error, {:restore_failed, %{reason: reason}}}
      end
    end
  end

  @doc """
  Return the path to the most recent backup, or nil if none exist.

  Options:
  - `:backups_dir` — override backups directory (DI, for testing)
  """
  @spec latest(keyword()) :: {:ok, String.t()} | {:error, {:no_backups, map()}}
  def latest(opts \\ []) do
    case list(opts) do
      {:ok, [newest | _]} -> {:ok, newest.path}
      {:ok, []} -> {:error, {:no_backups, %{}}}
    end
  end

  @doc """
  Delete backups exceeding the retention limit, keeping the newest.

  Options:
  - `:retention` — number of backups to keep (default: #{@default_retention})
  - `:backups_dir` — override backups directory (DI, for testing)
  """
  @spec prune(keyword()) :: {:ok, map()}
  def prune(opts \\ []) do
    retention = Keyword.get(opts, :retention, @default_retention)

    case list(opts) do
      {:ok, backups} when length(backups) > retention ->
        to_delete = Enum.drop(backups, retention)
        deleted = Enum.count(to_delete, &(File.rm(&1.path) == :ok))
        {:ok, %{deleted: deleted, kept: retention}}

      {:ok, backups} ->
        {:ok, %{deleted: 0, kept: length(backups)}}
    end
  end

  # -- Private --

  defp build_create_result(dest, filename, timestamp) do
    size =
      case File.stat(dest) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end

    %{path: dest, filename: filename, size: size, timestamp: timestamp}
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:backup_failed, %{reason: reason}}}
    end
  end

  defp verify_source(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, {:backup_failed, %{reason: :source_not_found, path: path}}}
    end
  end

  defp format_timestamp(datetime) do
    datetime
    |> DateTime.to_iso8601(:basic)
    |> String.replace(~r/[^0-9T]/, "")
    |> String.slice(0, 15)
  end

  defp build_backup_info(dir, filename) do
    path = Path.join(dir, filename)

    size =
      case File.stat(path) do
        {:ok, %{size: s}} -> s
        _ -> 0
      end

    %{
      path: path,
      filename: filename,
      size: size,
      timestamp: extract_timestamp(filename)
    }
  end

  defp extract_timestamp(filename) do
    case Regex.run(~r/^familiar-(.+)\.db$/, filename) do
      [_, ts] -> ts
      _ -> ""
    end
  end

  defp db_path(opts), do: Keyword.get(opts, :db_path, Paths.db_path())
  defp backups_dir(opts), do: Keyword.get(opts, :backups_dir, Paths.backups_dir())
end
