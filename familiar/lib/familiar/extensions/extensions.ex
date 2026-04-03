defmodule Familiar.Extensions do
  @moduledoc """
  Default extensions for the agent harness.

  Extensions implement the `Familiar.Extension` behaviour and are loaded
  at startup via `Familiar.Execution.ExtensionLoader`. This context
  contains the default extensions shipped with Familiar.
  """

  use Boundary,
    deps: [Familiar.Execution],
    exports: [Familiar.Extensions.Safety]
end
