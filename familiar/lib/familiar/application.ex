defmodule Familiar.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        FamiliarWeb.Telemetry,
        Familiar.Repo,
        {Task.Supervisor, name: Familiar.TaskSupervisor},
        {Ecto.Migrator,
         repos: Application.fetch_env!(:familiar, :ecto_repos), skip: skip_migrations?()},
        # Recovery gate — runs synchronously after Repo/Migrator, returns :ignore
        Familiar.Daemon.RecoveryGate,
        {DNSCluster, query: Application.get_env(:familiar, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Familiar.PubSub},
        # Daemon lifecycle — conditionally started (disabled in test env)
        if(Application.get_env(:familiar, :start_daemon, true),
          do: Familiar.Daemon.Server
        ),
        # Start to serve requests, typically the last entry
        FamiliarWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: Familiar.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FamiliarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
