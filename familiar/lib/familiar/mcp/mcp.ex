defmodule Familiar.MCP do
  @moduledoc """
  Model Context Protocol support.

  Provides JSON-RPC 2.0 codec and method dispatch for communicating with
  external MCP servers. Transport-agnostic — the client GenServer (Story 8-2)
  handles stdio/Port plumbing.
  """

  use Boundary,
    deps: [],
    exports: [Familiar.MCP.Protocol, Familiar.MCP.Dispatcher]
end
