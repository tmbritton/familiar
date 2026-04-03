defmodule Familiar.ActivityFormatter do
  @moduledoc """
  Pure function formatter for activity events.

  Converts `Activity.Event` structs to single-line strings suitable for
  terminal display. All output is guaranteed to fit within 80 columns.
  """

  alias Familiar.Activity.Event

  @max_width 80
  @indent "  "

  @doc """
  Format an activity event as a single-line string, max 80 characters.

  Accepts an optional `hint: true` keyword to append explanatory text
  for new users.
  """
  @spec format(Event.t(), keyword()) :: String.t()
  def format(%Event{} = event, opts \\ []) do
    hint = Keyword.get(opts, :hint, false)
    line = format_event(event)
    line = if hint, do: append_hint(line, event.type), else: line
    truncate_to_width(line)
  end

  @doc """
  Returns the heartbeat indicator string.
  """
  @spec heartbeat() :: String.t()
  def heartbeat do
    "#{@indent}..."
  end

  # -- Formatters per event type --

  defp format_event(%Event{type: :file_read, detail: path}) do
    "#{@indent}Reading #{path || "unknown"}"
  end

  defp format_event(%Event{type: :file_write, detail: path}) do
    "#{@indent}Writing #{path || "unknown"}"
  end

  defp format_event(%Event{type: :tool_call, detail: tool_name, result: result}) do
    suffix = if result, do: " → #{result}", else: ""
    "#{@indent}Tool: #{tool_name || "unknown"}#{suffix}"
  end

  defp format_event(%Event{type: :knowledge_search, detail: query}) do
    "#{@indent}Searching knowledge: #{query || "unknown"}"
  end

  defp format_event(%Event{type: :step_started, detail: step_name}) do
    "Starting: #{step_name || "step"}"
  end

  defp format_event(%Event{type: :step_complete, detail: step_name, result: result}) do
    suffix = if result, do: " (#{result})", else: ""
    "Completed: #{step_name || "step"}#{suffix}"
  end

  defp format_event(%Event{type: :agent_spawned, detail: role}) do
    "#{@indent}Spawned agent: #{role || "unknown"}"
  end

  defp format_event(%Event{type: :agent_complete, detail: role, result: result}) do
    suffix = if result, do: " — #{result}", else: ""
    "#{@indent}Agent done: #{role || "unknown"}#{suffix}"
  end

  defp format_event(%Event{type: :status, result: message}) do
    "#{@indent}#{message || "..."}"
  end

  defp format_event(%Event{type: type, detail: detail}) do
    suffix = if detail, do: ": #{detail}", else: ""
    "#{@indent}#{type}#{suffix}"
  end

  # -- Hints --

  defp append_hint(line, :file_read), do: "#{line} (checking file contents)"
  defp append_hint(line, :knowledge_search), do: "#{line} (querying project context)"
  defp append_hint(line, :tool_call), do: "#{line} (agent using a tool)"
  defp append_hint(line, :agent_spawned), do: "#{line} (worker started)"
  defp append_hint(line, _type), do: line

  # -- Helpers --

  defp truncate_to_width(line) do
    if String.length(line) <= @max_width do
      line
    else
      line
      |> String.graphemes()
      |> Enum.take(@max_width - 1)
      |> Enum.join()
      |> Kernel.<>("\u2026")
    end
  end
end
