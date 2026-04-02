defmodule Familiar.System.Clock do
  @moduledoc """
  Behaviour for time operations.

  Abstracts system clock so tests can use frozen or controllable time.
  """

  @doc "Return the current UTC datetime."
  @callback now() :: DateTime.t()
end
