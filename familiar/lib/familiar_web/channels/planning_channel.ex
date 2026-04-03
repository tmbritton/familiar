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
  alias Familiar.Planning.Trail
  alias Familiar.Planning.TrailFormatter

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

  @impl true
  def handle_in("generate_spec", %{"session_id" => session_id}, socket) do
    opts = engine_opts(socket)
    sid = normalize_session_id(session_id)

    # Subscribe to trail events before spawning the task
    {:ok, :subscribed} = Trail.subscribe(sid)

    # Run spec generation async so trail events can stream in real time
    Task.Supervisor.async_nolink(Familiar.TaskSupervisor, fn ->
      Engine.generate_spec(sid, opts)
    end)

    {:reply, {:ok, %{status: "generating", session_id: sid}}, socket}
  end

  @impl true
  def handle_info({:trail_event, event}, socket) do
    payload = %{
      type: to_string(event.type),
      text: TrailFormatter.format(event)
    }

    push(socket, "trail:event", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:ok, result}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    push(socket, "spec:complete", %{
      spec_id: result.spec.id,
      title: result.spec.title,
      file_path: result.file_path,
      verified: result.metadata.verified_count,
      unverified: result.metadata.unverified_count
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:error, {type, details}}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    push(socket, "spec:error", %{type: to_string(type), details: inspect(details)})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, socket) do
    push(socket, "spec:error", %{type: "task_crashed", details: inspect(reason)})
    {:noreply, socket}
  end

  defp normalize_resume(state) do
    Map.update(state, :status, nil, &to_string/1)
  end

  defp normalize_session_id(id) when is_integer(id), do: id
  defp normalize_session_id(id) when is_binary(id), do: String.to_integer(id)

  defp engine_opts(_socket) do
    Application.get_env(:familiar, :planning_engine_opts, [])
  end
end
