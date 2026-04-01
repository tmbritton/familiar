defmodule FamiliarWeb.Router do
  use FamiliarWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FamiliarWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FamiliarWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", FamiliarWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/daemon/status", DaemonController, :status
    post "/daemon/stop", DaemonController, :stop
  end
end
