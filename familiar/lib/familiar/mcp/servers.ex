defmodule Familiar.MCP.Servers do
  @moduledoc """
  Context module for managing persisted MCP server configurations.

  Provides CRUD operations on the `mcp_servers` table. All mutations
  return tagged tuples for consistent error handling.
  """

  import Ecto.Query, only: [order_by: 2]

  alias Familiar.MCP.Server
  alias Familiar.Repo

  @doc "List all MCP servers, ordered by name."
  @spec list() :: [Server.t()]
  def list do
    Server
    |> order_by(:name)
    |> Repo.all()
  end

  @doc "Get a server by name."
  @spec get(String.t()) :: {:ok, Server.t()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    case Repo.get_by(Server, name: name) do
      nil -> {:error, :not_found}
      server -> {:ok, server}
    end
  end

  @doc "Create a new MCP server."
  @spec create(map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) when is_map(attrs) do
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update an existing MCP server."
  @spec update(String.t(), map()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update(name, attrs) when is_binary(name) and is_map(attrs) do
    case get(name) do
      {:ok, server} ->
        server
        |> Server.changeset(attrs)
        |> Repo.update()

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc "Delete a server by name."
  @spec delete(String.t()) :: {:ok, Server.t()} | {:error, :not_found}
  def delete(name) when is_binary(name) do
    case get(name) do
      {:ok, server} -> Repo.delete(server)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc "Enable a server (set disabled=false)."
  @spec enable(String.t()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def enable(name) when is_binary(name) do
    update(name, %{disabled: false})
  end

  @doc "Disable a server (set disabled=true)."
  @spec disable(String.t()) :: {:ok, Server.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def disable(name) when is_binary(name) do
    update(name, %{disabled: true})
  end
end
