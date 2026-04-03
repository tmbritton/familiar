defmodule Familiar.Planning.TrailFormatter do
  @moduledoc """
  Pure function formatter for trail events.

  Converts `Trail.Event` structs to single-line strings suitable for
  terminal display. All output is guaranteed to fit within 80 columns.
  """

  alias Familiar.Planning.Trail.Event

  @max_width 80
  @indent "  "
  @indent_len 2

  @doc """
  Format a trail event as a single-line string, max 80 characters.

  Accepts an optional `hint: true` keyword to append explanatory text
  for new users (first ~3 planning sessions).
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

  defp format_event(%Event{type: :file_read, path: path}) do
    "#{@indent}Reading #{path || "unknown"}"
  end

  defp format_event(%Event{type: :knowledge_search, path: path}) do
    query = strip_knowledge_prefix(path)
    "#{@indent}Searching knowledge: #{query}"
  end

  defp format_event(%Event{type: :verification_result, result: result}) do
    case parse_verification_result(result) do
      {:verified, claim} -> "#{@indent}\u2713 Verified: #{claim}"
      {:unverified, claim} -> "#{@indent}\u26A0 Unverified: #{claim}"
      _ -> "#{@indent}Verification: #{result || "unknown"}"
    end
  end

  defp format_event(%Event{type: :spec_started}) do
    "Generating spec..."
  end

  defp format_event(%Event{type: :spec_complete, result: result}) do
    "Spec complete: #{result || "done"}"
  end

  defp format_event(%Event{type: type}) do
    "#{@indent}#{type}"
  end

  # -- Hints --

  defp append_hint(line, :file_read), do: "#{line} (checking file contents)"
  defp append_hint(line, :knowledge_search), do: "#{line} (querying project context)"

  defp append_hint(line, :verification_result) do
    if String.contains?(line, "\u2713") do
      "#{line} (confirmed by file read)"
    else
      "#{line} (no matching file read)"
    end
  end

  defp append_hint(line, _type), do: line

  # -- Helpers --

  defp strip_knowledge_prefix(nil), do: "unknown"
  defp strip_knowledge_prefix("knowledge:" <> query), do: query
  defp strip_knowledge_prefix(path), do: path

  defp parse_verification_result(nil), do: nil

  defp parse_verification_result(result) do
    case String.split(result, ": ", parts: 2) do
      ["verified", claim] -> {:verified, claim}
      ["unverified", claim] -> {:unverified, claim}
      _ -> nil
    end
  end

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
