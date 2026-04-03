defmodule Familiar.Execution.FileWatcher do
  @moduledoc """
  Watches the project directory for file changes and broadcasts events
  via the Hooks event system.

  Uses the `file_system` hex package (inotify on Linux, FSEvents on macOS)
  with per-file debouncing to coalesce rapid changes (editor save, formatter,
  linter) into a single event.

  This is a core harness process — it sits in the supervision tree directly,
  not loaded via ExtensionLoader.

  ## Events

  All file events broadcast as a single `:on_file_changed` hook with a
  `type` field to discriminate:

    * `%{path: path, type: :created}` — new file detected
    * `%{path: path, type: :changed}` — existing file modified
    * `%{path: path, type: :deleted}` — file removed

  ## Options

    * `:project_dir` — directory to watch (default: `File.cwd!/0`)
    * `:debounce_ms` — settle time per file in milliseconds (default: 500)
    * `:ignore_patterns` — list of path prefixes to ignore
      (default: `[".git/", "_build/", "deps/", "node_modules/", ".familiar/"]`)
    * `:name` — GenServer registration name (optional)
  """

  use GenServer

  require Logger

  @default_debounce_ms 500
  @default_ignore_patterns [".git/", "_build/", "deps/", "node_modules/", ".familiar/"]

  # -- Public API --

  @doc "Start the file watcher linked to the calling process."
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  # -- Server Callbacks --

  @impl true
  def init(opts) do
    project_dir = Keyword.get_lazy(opts, :project_dir, &File.cwd!/0)
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)
    ignore_patterns = Keyword.get(opts, :ignore_patterns, @default_ignore_patterns)

    if File.dir?(project_dir) do
      case FileSystem.start_link(dirs: [project_dir]) do
        {:ok, backend_pid} ->
          FileSystem.subscribe(backend_pid)

          Logger.info(
            "[FileWatcher] Watching #{project_dir} " <>
              "(ignore: #{inspect(ignore_patterns)}, debounce: #{debounce_ms}ms)"
          )

          state = %{
            project_dir: project_dir,
            backend_pid: backend_pid,
            debounce_ms: debounce_ms,
            ignore_patterns: normalize_patterns(ignore_patterns),
            pending: %{}
          }

          {:ok, state}

        {:error, reason} ->
          {:stop, {:backend_failed, reason}}
      end
    else
      {:stop, {:invalid_dir, project_dir}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    relative = Path.relative_to(path, state.project_dir)

    if ignored?(relative, state.ignore_patterns) do
      {:noreply, state}
    else
      event_type = classify_event(events)
      state = handle_event(state, path, event_type)
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[FileWatcher] Backend stopped unexpectedly")
    {:stop, :backend_stopped, state}
  end

  def handle_info({:debounce_fire, ref, path}, state) do
    case Map.get(state.pending, path) do
      {^ref, event_type} ->
        broadcast_event(event_type, path)
        {:noreply, %{state | pending: Map.delete(state.pending, path)}}

      _ ->
        # Stale timer — ref doesn't match current pending entry
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if Process.alive?(state.backend_pid) do
      Process.exit(state.backend_pid, :shutdown)
    end

    :ok
  end

  # -- Private --

  defp classify_event(flags) when is_list(flags) do
    cond do
      :created in flags -> :created
      :removed in flags or :deleted in flags -> :deleted
      true -> :changed
    end
  end

  # Deleted events fire immediately (no debounce) and cancel any pending timer
  defp handle_event(state, path, :deleted) do
    state = cancel_pending(state, path)
    broadcast_event(:deleted, path)
    state
  end

  # Created and changed events are debounced
  defp handle_event(state, path, event_type) do
    schedule_debounce(state, path, event_type)
  end

  defp schedule_debounce(state, path, event_type) do
    # Cancel existing timer and merge event type
    merged_type =
      case Map.get(state.pending, path) do
        {old_ref, prev_type} ->
          Process.cancel_timer(old_ref)
          merge_event_types(prev_type, event_type)

        nil ->
          event_type
      end

    ref = make_ref()
    Process.send_after(self(), {:debounce_fire, ref, path}, state.debounce_ms)
    %{state | pending: Map.put(state.pending, path, {ref, merged_type})}
  end

  defp cancel_pending(state, path) do
    case Map.pop(state.pending, path) do
      {{old_ref, _}, pending} ->
        Process.cancel_timer(old_ref)
        %{state | pending: pending}

      {nil, _} ->
        state
    end
  end

  # Created + changed during debounce window → still a creation
  defp merge_event_types(:created, :changed), do: :created
  # Otherwise use the newest type
  defp merge_event_types(_, new), do: new

  defp broadcast_event(event_type, path) do
    Familiar.Hooks.event(:on_file_changed, %{path: path, type: event_type})
  end

  defp ignored?(relative_path, patterns) do
    components = Path.split(relative_path)

    Enum.any?(patterns, fn pattern ->
      # Pattern is normalized to "dir/" — strip trailing slash for component match
      dir_name = String.trim_trailing(pattern, "/")
      Enum.any?(components, &(&1 == dir_name))
    end)
  end

  defp normalize_patterns(patterns) do
    Enum.map(patterns, fn pattern ->
      pattern
      |> String.trim_trailing("/")
      |> Kernel.<>("/")
    end)
  end
end
