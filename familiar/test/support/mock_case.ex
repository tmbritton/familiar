defmodule Familiar.MockCase do
  @moduledoc """
  ExUnit case template for tests that use Mox behaviour mocks.

  Sets up Mox.verify_on_exit! for all tests and imports common
  mock helpers. Safe for both sync and async tests.

  ## Usage

      use Familiar.MockCase
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Mox
    end
  end

  setup context do
    Mox.verify_on_exit!(context)
    :ok
  end
end
