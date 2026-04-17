defmodule Familiar.Extension do
  @moduledoc """
  Behaviour for harness extensions.

  Extensions register tools, lifecycle hooks, and optional supervision children.
  The Knowledge Store is the default extension — it implements this
  behaviour like any third-party extension.

  ## Callbacks

    * `name/0` — unique string identifier
    * `tools/0` — tool registrations for the ToolRegistry
    * `hooks/0` — lifecycle hook registrations (alter or event)
    * `child_spec/1` — optional supervision child spec
    * `init/1` — extension-specific setup, called at load time

  ## Hook Types

    * `:alter` — synchronous pipeline; handlers can modify payload or veto with `{:halt, reason}`
    * `:event` — async broadcast via PubSub; fire-and-forget, crash-isolated

  ## Example

      defmodule MyExtension do
        @behaviour Familiar.Extension

        @impl true
        def name, do: "my-extension"

        @impl true
        def tools, do: [{:my_tool, &my_tool_fn/2, "Does something useful"}]

        @impl true
        def hooks do
          [
            %{hook: :before_tool_call, handler: &handle_before_tool/2, priority: 50, type: :alter},
            %{hook: :on_agent_complete, handler: &handle_complete/1, priority: 100, type: :event}
          ]
        end

        @impl true
        def init(_opts), do: :ok

        # ...
      end
  """

  @type tool_registration ::
          {atom(), function(), String.t()} | {atom(), function(), String.t(), map()}

  @type hook_registration :: %{
          hook: atom(),
          handler: function(),
          priority: integer(),
          type: :alter | :event
        }

  @doc "Unique name for this extension."
  @callback name() :: String.t()

  @doc "Tool registrations: `{name, implementation_fn, description}`."
  @callback tools() :: [tool_registration()]

  @doc "Lifecycle hook registrations."
  @callback hooks() :: [hook_registration()]

  @doc "Supervisor child spec, or `nil` if no supervision needed."
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec() | nil

  @doc "Extension-specific initialization. Called once at load time."
  @callback init(opts :: keyword()) :: :ok | {:error, term()}

  @optional_callbacks [child_spec: 1]
end
