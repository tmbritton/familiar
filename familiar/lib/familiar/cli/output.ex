defmodule Familiar.CLI.Output do
  @moduledoc """
  CLI output formatting with JSON envelope, text, and quiet modes.

  JSON envelope contract:
  - Success: `{"data": ...}`
  - Error: `{"error": {"type": "...", "message": "...", "details": {...}}}`

  All JSON uses `snake_case` field names.
  """

  @usage_error_types [:unknown_command, :usage_error]

  @doc """
  Format a result tuple for CLI output.

  Accepts `{:ok, data}` or `{:error, {type, details}}` with a format mode
  of `:json`, `:text`, or `:quiet`. An optional text formatter function
  can be provided for `:text` mode.
  """
  @spec format(
          {:ok, term()} | {:error, {atom(), map()}},
          :json | :text | :quiet,
          function() | nil
        ) ::
          String.t()
  def format(result, mode, text_formatter \\ nil)

  def format({:ok, data}, :json, _formatter) do
    Jason.encode!(%{data: data})
  end

  def format({:error, {type, details}}, :json, _formatter) do
    Jason.encode!(%{
      error: %{
        type: to_string(type),
        message: error_message(type, details),
        details: details
      }
    })
  end

  def format({:ok, data}, :text, nil) do
    inspect(data, pretty: true)
  end

  def format({:ok, data}, :text, formatter) when is_function(formatter, 1) do
    formatter.(data)
  end

  def format({:error, {type, details}}, :text, _formatter) do
    friendly = error_message(type, details)
    type_str = to_string(type)

    if friendly == type_str do
      # `error_message/2` falls through to `to_string(type)` for unknown
      # error types — keep the historical "Error [type] — %{...}" shape so
      # operator-visible context isn't lost on unrecognized errors.
      detail_str =
        case details do
          details when details == %{} -> ""
          details -> " — #{inspect(details)}"
        end

      "Error [#{type}]#{detail_str}"
    else
      "Error [#{type}] #{friendly}"
    end
  end

  def format({:ok, data}, :quiet, _formatter) do
    quiet_summary(data)
  end

  def format({:error, {type, _details}}, :quiet, _formatter) do
    "error: #{type}"
  end

  @doc "Write formatted output to IO device."
  @spec puts(String.t(), IO.device()) :: :ok
  def puts(output, device \\ :stdio) do
    IO.puts(device, output)
  end

  @doc """
  Determine exit code from a result tuple.

  - 0 for success
  - 1 for general errors
  - 2 for usage errors (unknown command, bad arguments)
  """
  @spec exit_code({:ok, term()} | {:error, {atom(), map()}}) :: 0 | 1 | 2
  def exit_code({:ok, _}), do: 0

  def exit_code({:error, {type, _}}) when type in @usage_error_types, do: 2

  def exit_code({:error, _}), do: 1

  # -- Private --

  defp quiet_summary(%{version: v}), do: v
  defp quiet_summary(%{daemon: s}), do: s
  defp quiet_summary(%{chat: _, status: s}), do: "chat:#{s}"
  defp quiet_summary(%{status: s}), do: s
  defp quiet_summary(%{id: id, status: "edited"}), do: "edited:#{id}"
  defp quiet_summary(%{id: id, status: "deleted"}), do: "deleted:#{id}"
  defp quiet_summary(%{id: id, text: _, type: _}), do: "entry:#{id}"
  defp quiet_summary(%{restored: f, status: _}), do: "restored:#{f}"
  defp quiet_summary(%{path: p, size: _, filename: _}), do: "backup:#{p}"
  defp quiet_summary(%{entry_count: c, signal: s, command: "status"}), do: "status:#{s}:#{c}"
  defp quiet_summary(%{entry_count: c, signal: s}), do: "health:#{s}:#{c}"
  defp quiet_summary(list) when is_list(list), do: "backups:#{length(list)}"
  defp quiet_summary(%{scanned: s}), do: "refreshed:#{s}"
  defp quiet_summary(%{candidates: c}), do: "candidates:#{length(c)}"
  defp quiet_summary(%{results: results, query: _}), do: "results:#{length(results)}"
  defp quiet_summary(%{files_scanned: n}), do: "scanned:#{n}"
  defp quiet_summary(%{conventions: c}), do: "conventions:#{length(c)}"
  defp quiet_summary(%{roles: r}), do: "roles:#{length(r)}"
  defp quiet_summary(%{role: %{name: n}}), do: "role:#{n}"
  defp quiet_summary(%{skills: s}), do: "skills:#{length(s)}"
  defp quiet_summary(%{skill: %{name: n}}), do: "skill:#{n}"
  defp quiet_summary(%{workflows: w}), do: "workflows:#{length(w)}"
  defp quiet_summary(%{workflow: %{name: n, steps: s}}), do: "workflow:#{n}:#{length(s)}"
  defp quiet_summary(%{workflow: w, steps: s}), do: "workflow:#{w}:#{length(s)}"
  defp quiet_summary(%{extensions: e}), do: "extensions:#{length(e)}"
  defp quiet_summary(%{sessions: s}), do: "sessions:#{length(s)}"
  defp quiet_summary(%{session: %{id: id}}), do: "session:#{id}"
  defp quiet_summary(%{cleaned: n}), do: "cleaned:#{n}"

  defp quiet_summary(%{validation: %{summary: s}}),
    do: "validate:#{s.passed}ok:#{s.warnings}warn:#{s.errors}err"

  defp quiet_summary(%{provider: _}), do: "ok"
  defp quiet_summary(%{help: _}), do: "ok"
  defp quiet_summary(_), do: "ok"

  defp error_message(:daemon_unavailable, _), do: "Daemon is not running and could not be started"
  defp error_message(:timeout, _), do: "Daemon did not respond within the timeout period"

  defp error_message(:version_mismatch, %{cli: cli, daemon: daemon}),
    do: "CLI version #{cli} is incompatible with daemon version #{daemon}"

  defp error_message(:init_required, _),
    do: "No .familiar/ directory found. Run `fam init` to initialize"

  defp error_message(:prerequisites_failed, %{instructions: instructions}), do: instructions

  defp error_message(:already_initialized, _),
    do: "Project already initialized. .familiar/ directory exists"

  defp error_message(:init_failed, %{reason: reason}),
    do: "Initialization failed: #{reason}"

  defp error_message(:invalid_config, %{field: field, reason: reason}),
    do: "Invalid configuration: #{field} — #{reason}"

  defp error_message(:workflow_timeout, _),
    do: "Session timed out. Run the command again to continue."

  defp error_message(:chat_timeout, _),
    do: "Chat session timed out. Run `fam chat --resume` to continue."

  defp error_message(:not_found, %{id: id}), do: "Entry not found: #{id}"
  defp error_message(:not_found, _), do: "Entry not found"

  defp error_message(:knowledge_not_code, _),
    do: "Content rejected: appears to be code, not knowledge"

  defp error_message(:delete_failed, _), do: "Failed to delete entry"
  defp error_message(:backup_failed, %{reason: r}), do: "Backup failed: #{r}"
  defp error_message(:restore_failed, %{reason: r}), do: "Restore failed: #{r}"
  defp error_message(:no_backups, _), do: "No backups available"
  defp error_message(:cancelled, _), do: "Restore cancelled"
  defp error_message(:unknown_command, %{command: cmd}), do: "Unknown command: #{cmd}"
  defp error_message(:usage_error, %{message: msg}), do: msg

  # -- Story 7.5-6 resume errors --

  defp error_message(:no_resumable_workflow, _),
    do:
      "No resumable workflow runs found. " <>
        "Use `fam workflows list-runs` to see all runs, or start a new one with `fam plan/do/fix`."

  defp error_message(:workflow_run_not_found, %{id: id}),
    do:
      "Workflow run ##{id} does not exist. " <>
        "Use `fam workflows list-runs` to see available runs."

  defp error_message(:workflow_already_completed, %{id: id}),
    do:
      "Workflow run ##{id} has already completed. " <>
        "Start a new run with `fam plan/do/fix` or `fam workflows run <path>`."

  defp error_message(:workflow_path_missing, %{id: id}),
    do:
      "Workflow run ##{id} has no source workflow path on file — it cannot be resumed. " <>
        "This happens when a run was started via `run_workflow_parsed` rather than " <>
        "`run_workflow(path, ...)`."

  defp error_message(:workflow_finalize_failed, %{id: id, reason: reason}),
    do:
      "Workflow run ##{id} is stuck past its final step but could not be marked completed " <>
        "(#{inspect(reason, limit: 50)}). Investigate the database or remove the row manually."

  defp error_message(type, _), do: to_string(type)
end
