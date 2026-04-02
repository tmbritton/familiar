defmodule Familiar.Daemon.Recovery do
  @moduledoc """
  Crash recovery gate.

  Runs as a synchronous function call during Application.start/2,
  BEFORE the supervision tree starts. Ensures the system is in a
  known-good state before any processes begin.

  Three-phase recovery:
  1. Database integrity check (PRAGMA integrity_check)
  2. File transaction rollback (stub — Story 5.2)
  3. Orphaned task reconciliation (stub — Story 4.1a)
  """

  require Logger

  alias Familiar.Daemon.ShutdownMarker

  @doc """
  Run crash recovery if an unclean shutdown is detected.

  Returns `:ok` regardless — recovery is best-effort. Errors in
  individual phases are logged but do not prevent startup.
  """
  @spec run_if_needed() :: :ok
  def run_if_needed do
    if ShutdownMarker.unclean_shutdown?() do
      Logger.warning("[Recovery] Unclean shutdown detected — running crash recovery")

      case run() do
        :ok ->
          ShutdownMarker.clear()
          Logger.info("[Recovery] Recovery completed — marker cleared")

        :error ->
          Logger.error(
            "[Recovery] Recovery had failures — marker NOT cleared (will retry on next start)"
          )
      end
    else
      Logger.info("[Recovery] Clean startup — no recovery needed")
    end

    :ok
  end

  @doc """
  Execute the three-phase recovery sequence.

  Each phase runs independently — failure in one does not prevent the
  next from running.
  """
  @spec run() :: :ok | :error
  def run do
    results = [
      run_phase("Database integrity check", &check_database_integrity/0),
      run_phase("File transaction rollback", &rollback_incomplete_transactions/0),
      run_phase("Orphaned task reconciliation", &reconcile_orphaned_tasks/0)
    ]

    if Enum.any?(results, &(&1 == :error)), do: :error, else: :ok
  end

  @doc false
  def check_database_integrity do
    # Run SQLite PRAGMA integrity_check
    # Full backup/restore comes in Story 2.5
    case Familiar.Repo.query("PRAGMA integrity_check") do
      {:ok, %{rows: [["ok"]]}} ->
        Logger.info("[Recovery] Database integrity check: OK")
        :ok

      {:ok, %{rows: rows}} ->
        Logger.error("[Recovery] Database integrity check failed: #{inspect(rows)}")
        {:error, {:storage_failed, %{reason: :integrity_check_failed, details: rows}}}

      {:error, reason} ->
        Logger.error("[Recovery] Database integrity check error: #{inspect(reason)}")
        {:error, {:storage_failed, %{reason: reason}}}
    end
  rescue
    e ->
      Logger.warning("[Recovery] Database integrity check skipped: #{Exception.message(e)}")
      :ok
  end

  @doc false
  def rollback_incomplete_transactions do
    # Stub — real implementation in Story 5.2 (File Transaction Module)
    Logger.info("[Recovery] No file transactions to rollback (stub)")
    :ok
  end

  @doc false
  def reconcile_orphaned_tasks do
    # Stub — real implementation in Story 4.1a (Task State Machine)
    Logger.info("[Recovery] No orphaned tasks found (stub)")
    :ok
  end

  # -- Private --

  defp run_phase(name, fun) do
    Logger.info("[Recovery] Starting: #{name}")

    case fun.() do
      :ok ->
        Logger.info("[Recovery] Completed: #{name}")
        :ok

      {:error, {type, details}} ->
        Logger.error("[Recovery] Failed: #{name} — #{type}: #{inspect(details)}")
        :error
    end
  rescue
    e ->
      Logger.error("[Recovery] Crashed: #{name} — #{Exception.message(e)}")
      :error
  end
end
