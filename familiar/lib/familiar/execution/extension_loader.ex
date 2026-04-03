defmodule Familiar.Execution.ExtensionLoader do
  @moduledoc """
  Loads extensions from application config at startup.

  Iterates configured extension modules, calls `init/1`, and collects
  tool registrations, hook registrations, and child specs. Failed
  extensions are logged and skipped — they do not crash the system.
  """

  require Logger

  alias Familiar.Hooks

  @doc """
  Load all configured extensions.

  For each module:
  1. Calls `init/1` — skips on failure
  2. Collects `tools/0` registrations
  3. Registers `hooks/0` with `Familiar.Hooks`
  4. Collects `child_spec/1` if defined

  Returns `{:ok, %{tools: [...], child_specs: [...], loaded: [...], failed: [...]}}`.
  """
  @spec load_extensions([module()], keyword()) ::
          {:ok,
           %{
             tools: [{atom(), function(), String.t()}],
             child_specs: [Supervisor.child_spec()],
             loaded: [String.t()],
             failed: [{module(), term()}]
           }}
  def load_extensions(extension_modules, opts \\ []) do
    result =
      Enum.reduce(
        extension_modules,
        %{tools: [], child_specs: [], loaded: [], failed: []},
        fn mod, acc ->
          case load_one(mod, opts) do
            {:ok, registration} ->
              %{
                acc
                | tools: acc.tools ++ registration.tools,
                  child_specs: acc.child_specs ++ registration.child_specs,
                  loaded: [registration.name | acc.loaded]
              }

            {:error, reason} ->
              Logger.warning(
                "[ExtensionLoader] Failed to load #{inspect(mod)}: #{inspect(reason)}"
              )

              %{acc | failed: [{mod, reason} | acc.failed]}
          end
        end
      )

    {:ok, %{result | loaded: Enum.reverse(result.loaded), failed: Enum.reverse(result.failed)}}
  end

  defp load_one(mod, opts) do
    with :ok <- validate_behaviour(mod),
         :ok <- call_init(mod, opts) do
      name = mod.name()
      tools = mod.tools()
      hooks = mod.hooks()

      child_specs = collect_child_spec(mod, opts)

      register_hooks(hooks, name)

      {:ok, %{name: name, tools: tools, child_specs: child_specs}}
    end
  end

  defp collect_child_spec(mod, opts) do
    if function_exported?(mod, :child_spec, 1) do
      case mod.child_spec(opts) do
        nil -> []
        spec -> [spec]
      end
    else
      []
    end
  end

  defp validate_behaviour(mod) do
    required = [:name, :tools, :hooks, :init]

    missing =
      Enum.reject(required, fn callback ->
        arity = if callback == :init, do: 1, else: 0
        function_exported?(mod, callback, arity)
      end)

    case missing do
      [] ->
        :ok

      fields ->
        {:error,
         {:missing_callbacks,
          "module #{inspect(mod)} missing: #{Enum.map_join(fields, ", ", &to_string/1)}"}}
    end
  end

  defp call_init(mod, opts) do
    case mod.init(opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:init_failed, reason}}
    end
  rescue
    error ->
      {:error, {:init_crashed, Exception.message(error)}}
  end

  defp register_hooks(hooks, extension_name) do
    for hook_reg <- hooks do
      case hook_reg.type do
        :alter ->
          priority = Map.get(hook_reg, :priority, 100)
          Hooks.register_alter_hook(hook_reg.hook, hook_reg.handler, priority, extension_name)

        :event ->
          Hooks.register_event_hook(hook_reg.hook, hook_reg.handler, extension_name)
      end
    end
  end
end
