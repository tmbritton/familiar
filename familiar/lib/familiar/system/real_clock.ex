defmodule Familiar.System.RealClock do
  @moduledoc """
  Production implementation of the Clock behaviour.

  Delegates to `DateTime.utc_now/0`.
  """

  @behaviour Familiar.System.Clock

  @impl true
  def now, do: DateTime.utc_now()
end
