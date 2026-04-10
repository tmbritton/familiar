defmodule Familiar.Execution.WorkflowRuns.JSONField do
  @moduledoc """
  Ecto.Type backing `workflow_runs.step_results` and `workflow_runs.initial_context`.

  Encodes Elixir maps/lists to JSON text on write and decodes on read.
  On decode failure we log a warning and fall back to a neutral default
  so a single malformed row doesn't break the entire context module —
  this is harness state, not source-of-truth user data.
  """

  use Ecto.Type

  require Logger

  @impl true
  def type, do: :string

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_map(value) or is_list(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.warning(
          "[WorkflowRuns.JSONField] Failed to decode stored JSON, returning empty list: #{inspect(reason)}"
        )

        # Return [] (not nil) so consumers like `Enum.reverse/1` and
        # `Enum.map/2` don't crash on a corrupted row. Both fields backed by
        # this type (`step_results`, `initial_context`) treat an empty list
        # as semantically equivalent to "no data" — for `step_results` this
        # is exact; for `initial_context` it's a graceful degradation
        # (callers fall back to `%{}` via `||` defaulting).
        {:ok, []}
    end
  end

  def load(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_map(value) or is_list(value) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> :error
    end
  end

  def dump(_), do: :error
end
