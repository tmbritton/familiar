defmodule FamiliarWeb.HealthController do
  use FamiliarWeb, :controller

  @doc "Health check endpoint for daemon status and version."
  def index(conn, _params) do
    version =
      case Application.spec(:familiar, :vsn) do
        nil -> "0.0.0"
        vsn -> to_string(vsn)
      end

    json(conn, %{status: "ok", version: version})
  end
end
