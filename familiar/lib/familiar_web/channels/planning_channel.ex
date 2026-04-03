defmodule FamiliarWeb.PlanningChannel do
  @moduledoc """
  Phoenix Channel for planning conversations.

  Planning commands are stubbed pending the workflow runner (Epic 5).
  The channel will be rewired to dispatch planning as a workflow
  in Epic 3r.
  """

  use FamiliarWeb, :channel

  @impl true
  def join("planning:lobby", _params, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("start_plan", _params, socket) do
    {:reply,
     {:error,
      %{reason: "not_implemented", message: "Planning will use the workflow runner (Epic 5)"}},
     socket}
  end

  @impl true
  def handle_in("respond", _params, socket) do
    {:reply,
     {:error,
      %{reason: "not_implemented", message: "Planning will use the workflow runner (Epic 5)"}},
     socket}
  end

  @impl true
  def handle_in("resume", _params, socket) do
    {:reply,
     {:error,
      %{reason: "not_implemented", message: "Planning will use the workflow runner (Epic 5)"}},
     socket}
  end

  @impl true
  def handle_in("generate_spec", _params, socket) do
    {:reply,
     {:error,
      %{
        reason: "not_implemented",
        message: "Spec generation will use the workflow runner (Epic 5)"
      }}, socket}
  end
end
