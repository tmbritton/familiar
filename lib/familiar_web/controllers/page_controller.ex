defmodule FamiliarWeb.PageController do
  use FamiliarWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
