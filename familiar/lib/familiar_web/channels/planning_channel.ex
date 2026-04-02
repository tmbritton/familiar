defmodule FamiliarWeb.PlanningChannel do
  @moduledoc """
  Phoenix Channel for planning conversations.

  Provides bidirectional streaming for the interactive planning loop:
  start_plan → question → respond → question → ... → spec_ready.

  This channel is the WebSocket transport for external integrations.
  The CLI calls `Planning.Engine` directly (in-process with the daemon).
  """

  use FamiliarWeb, :channel

  alias Familiar.Planning.Engine

  @impl true
  def join("planning:lobby", _params, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("start_plan", %{"description" => description}, socket) do
    opts = engine_opts(socket)

    case Engine.start_plan(description, opts) do
      {:ok, result} ->
        reply = %{session_id: result.session_id, response: result.response, status: to_string(result.status)}
        {:reply, {:ok, reply}, socket}

      {:error, {type, details}} ->
        {:reply, {:error, %{type: to_string(type), details: inspect(details)}}, socket}
    end
  end

  @impl true
  def handle_in("respond", %{"session_id" => session_id, "message" => message}, socket) do
    opts = engine_opts(socket)

    case Engine.respond(session_id, message, opts) do
      {:ok, result} ->
        reply = %{session_id: result.session_id, response: result.response, status: to_string(result.status)}
        {:reply, {:ok, reply}, socket}

      {:error, {type, details}} ->
        {:reply, {:error, %{type: to_string(type), details: inspect(details)}}, socket}
    end
  end

  @impl true
  def handle_in("resume", %{"session_id" => session_id}, socket) do
    case Engine.resume(session_id) do
      {:ok, state} ->
        {:reply, {:ok, normalize_resume(state)}, socket}

      {:error, {type, details}} ->
        {:reply, {:error, %{type: to_string(type), details: inspect(details)}}, socket}
    end
  end

  @impl true
  def handle_in("resume", %{}, socket) do
    case Engine.latest_active_session() do
      {:ok, session_id} ->
        case Engine.resume(session_id) do
          {:ok, state} ->
            {:reply, {:ok, normalize_resume(state)}, socket}

          {:error, {type, details}} ->
            {:reply, {:error, %{type: to_string(type), details: inspect(details)}}, socket}
        end

      {:error, {type, details}} ->
        {:reply, {:error, %{type: to_string(type), details: inspect(details)}}, socket}
    end
  end

  defp normalize_resume(state) do
    Map.update(state, :status, nil, &to_string/1)
  end

  defp engine_opts(_socket) do
    Application.get_env(:familiar, :planning_engine_opts, [])
  end
end
