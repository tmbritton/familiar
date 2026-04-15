defmodule Familiar.MCP do
  @moduledoc """
  Model Context Protocol support.

  Provides JSON-RPC 2.0 codec, method dispatch, and client connections
  for communicating with external MCP servers over stdio.
  """

  use Boundary,
    deps: [Familiar.Execution],
    exports: [
      Familiar.MCP.Protocol,
      Familiar.MCP.Dispatcher,
      Familiar.MCP.Client,
      Familiar.MCP.ClientSupervisor,
      Familiar.MCP.Server,
      Familiar.MCP.Servers
    ]
end
