defmodule FamiliarWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix Channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import FamiliarWeb.ChannelCase

      @endpoint FamiliarWeb.Endpoint
    end
  end

  setup tags do
    Familiar.DataCase.setup_sandbox(tags)
    Mox.stub(Familiar.System.ClockMock, :now, fn -> DateTime.utc_now() end)
    :ok
  end
end
