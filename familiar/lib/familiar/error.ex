defmodule Familiar.Error do
  @moduledoc """
  Error classification for the self-repair decision engine.

  The `recoverable?/1` function drives retry behavior:
  - `true` → system retries/auto-repairs before involving the user
  - `false` → escalate to user as ❌ (needs input)

  Error tuples follow the convention: `{:error, {atom_type, map_details}}`.
  """

  @doc """
  Determines whether an error is recoverable (retryable) or requires
  human intervention.

  ## Examples

      iex> Familiar.Error.recoverable?({:provider_unavailable, %{}})
      true

      iex> Familiar.Error.recoverable?({:file_conflict, %{}})
      false
  """
  @spec recoverable?({atom(), map()}) :: boolean()
  def recoverable?({:provider_unavailable, _}), do: true
  def recoverable?({:validation_failed, _}), do: true
  def recoverable?({:file_conflict, _}), do: false
  def recoverable?({:not_found, _}), do: false
  def recoverable?({:invalid_config, _}), do: false
  def recoverable?({:storage_failed, _}), do: false
  def recoverable?({:query_failed, _}), do: false
  def recoverable?(_), do: false
end
