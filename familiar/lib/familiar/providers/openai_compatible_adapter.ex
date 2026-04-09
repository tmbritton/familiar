defmodule Familiar.Providers.OpenAICompatibleAdapter do
  @moduledoc """
  OpenAI-compatible LLM provider adapter.

  Works with any provider that implements the `/v1/chat/completions` API:
  DeepSeek, Qwen (Dashscope), OpenRouter, Groq, Together, etc.

  ## Configuration

  Set via environment variables:

      FAMILIAR_API_KEY=sk-xxx
      FAMILIAR_BASE_URL=https://api.deepseek.com
      FAMILIAR_CHAT_MODEL=deepseek-chat

  Or via application config:

      config :familiar, :openai_compatible,
        api_key: "sk-xxx",
        base_url: "https://api.deepseek.com",
        chat_model: "deepseek-chat"
  """

  @behaviour Familiar.Providers.LLM

  require Logger

  @default_base_url "https://api.deepseek.com"
  @default_chat_model "deepseek-chat"
  @default_receive_timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    body = build_request_body(messages, opts)

    case Req.post(base_url() <> "/v1/chat/completions",
           json: body,
           headers: auth_headers(),
           receive_timeout: receive_timeout(opts)
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %Req.Response{status: 401}} ->
        {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :unauthorized}}}

      {:ok, %Req.Response{status: 429}} ->
        {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :rate_limited}}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         {:provider_unavailable,
          %{provider: :openai_compatible, reason: :api_error, status: status, body: body}}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error,
         {:provider_unavailable, %{provider: :openai_compatible, reason: :connection_refused}}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :timeout}}}

      {:error, reason} ->
        {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: reason}}}
    end
  end

  @impl true
  def stream_chat(_messages, _opts \\ []) do
    {:error,
     {:not_implemented,
      %{message: "Streaming not yet implemented for OpenAI-compatible providers."}}}
  end

  # -- Private: Request --

  defp build_request_body(messages, opts) do
    body = %{
      model: chat_model(opts),
      messages: format_messages(messages)
    }

    tools = build_tool_schemas(opts)
    if tools == [], do: body, else: Map.put(body, :tools, tools)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      role = to_string(Map.get(msg, :role, Map.get(msg, "role", "user")))
      content = to_string(Map.get(msg, :content, Map.get(msg, "content", "")))
      %{"role" => role, "content" => content}
    end)
  end

  defp build_tool_schemas(opts) do
    case Keyword.get(opts, :tools) do
      nil -> []
      tools when is_list(tools) -> Enum.map(tools, &format_tool_schema/1)
    end
  end

  defp format_tool_schema(tool) when is_map(tool), do: tool

  defp format_tool_schema(name) when is_binary(name) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => "Tool: #{name}",
        "parameters" => %{"type" => "object", "properties" => %{}}
      }
    }
  end

  # -- Private: Response --

  defp parse_response(%{"choices" => [choice | _]}) do
    message = Map.get(choice, "message", %{})
    content = Map.get(message, "content") || ""
    raw_tool_calls = Map.get(message, "tool_calls") || []

    tool_calls = Enum.map(raw_tool_calls, &parse_tool_call/1)

    usage = Map.get(choice, "usage", %{})

    %{
      content: content,
      tool_calls: tool_calls,
      usage: %{
        prompt_tokens: Map.get(usage, "prompt_tokens"),
        completion_tokens: Map.get(usage, "completion_tokens")
      }
    }
  end

  defp parse_response(_body) do
    %{content: "", tool_calls: []}
  end

  defp parse_tool_call(%{"function" => %{"name" => name, "arguments" => args}} = tc) do
    parsed_args =
      case args do
        a when is_binary(a) ->
          case Jason.decode(a) do
            {:ok, decoded} -> decoded
            {:error, _} -> %{}
          end

        a when is_map(a) ->
          a

        _ ->
          %{}
      end

    %{
      "id" => Map.get(tc, "id"),
      "type" => "function",
      "function" => %{"name" => name, "arguments" => parsed_args}
    }
  end

  defp parse_tool_call(tc), do: tc

  # -- Private: Auth --

  defp auth_headers do
    [{"authorization", "Bearer #{api_key()}"}]
  end

  # -- Private: Config --
  # Priority: opts > env vars > config.toml provider > application config > defaults

  defp api_key do
    System.get_env("FAMILIAR_API_KEY") ||
      project_config(:api_key) ||
      app_config(:api_key) ||
      raise "No API key configured. Set api_key in .familiar/config.toml or FAMILIAR_API_KEY env var."
  end

  defp base_url do
    System.get_env("FAMILIAR_BASE_URL") ||
      project_config(:base_url) ||
      app_config(:base_url) ||
      @default_base_url
  end

  defp chat_model(opts) do
    Keyword.get_lazy(opts, :model, fn ->
      System.get_env("FAMILIAR_CHAT_MODEL") ||
        project_config(:chat_model) ||
        app_config(:chat_model) ||
        @default_chat_model
    end)
  end

  defp receive_timeout(opts) do
    Keyword.get(opts, :receive_timeout, @default_receive_timeout)
  end

  defp project_config(key) do
    load_project_config() |> Map.get(key)
  end

  defp load_project_config do
    config_path =
      Path.join([
        Application.get_env(:familiar, :project_dir) ||
          System.get_env("FAMILIAR_PROJECT_DIR") ||
          File.cwd!(),
        ".familiar",
        "config.toml"
      ])

    case Familiar.Config.load(config_path) do
      {:ok, config} -> config.provider
      _ -> %{}
    end
  end

  defp app_config(key) do
    Application.get_env(:familiar, :openai_compatible, [])
    |> Keyword.get(key)
  end
end
