defmodule Familiar.Providers.OllamaAdapter do
  @moduledoc """
  Ollama LLM provider adapter.

  Implements `Familiar.Providers.LLM` behaviour by communicating with
  the Ollama HTTP API. Streaming responses are normalized to the common
  `StreamEvent.t()` format.
  """

  @behaviour Familiar.Providers.LLM

  @default_base_url "http://localhost:11434"
  @default_receive_timeout 120_000

  @impl true
  def chat(messages, opts \\ []) do
    body = build_chat_body(messages, opts, _stream = false)

    case Req.post(base_url() <> "/api/chat",
           json: body,
           receive_timeout: receive_timeout(opts)
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_chat_response(body)}

      {:ok, %Req.Response{status: 404}} ->
        {:error,
         {:provider_unavailable,
          %{provider: :ollama, reason: :model_not_found, model: chat_model(opts)}}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error,
         {:provider_unavailable,
          %{provider: :ollama, reason: :api_error, status: status, body: body}}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :connection_refused}}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}

      {:error, reason} ->
        {:error, {:provider_unavailable, %{provider: :ollama, reason: reason}}}
    end
  end

  @impl true
  def stream_chat(messages, opts \\ []) do
    body = build_chat_body(messages, opts, _stream = true)
    caller = self()
    ref = make_ref()
    timeout = receive_timeout(opts)

    pid =
      spawn(fn ->
        try do
          result =
            Req.post(base_url() <> "/api/chat",
              json: body,
              receive_timeout: timeout,
              into: fn {:data, data}, {req, resp} ->
                send(caller, {:ollama_chunk, ref, data})
                {:cont, {req, resp}}
              end
            )

          case result do
            {:ok, _} -> send(caller, {:ollama_stream_end, ref})
            {:error, reason} -> send(caller, {:ollama_stream_error, ref, reason})
          end
        rescue
          e -> send(caller, {:ollama_stream_error, ref, e})
        end
      end)

    stream =
      Stream.resource(
        fn -> %{ref: ref, pid: pid, buffer: "", done: false, timeout: timeout} end,
        fn state -> receive_stream_chunk(state) end,
        fn state -> cleanup_stream(state) end
      )

    {:ok, stream}
  end

  # -- Private: Streaming --

  defp receive_stream_chunk(%{done: true} = state), do: {:halt, state}

  defp receive_stream_chunk(state) do
    receive do
      {:ollama_chunk, ref, data} when ref == state.ref ->
        {events, new_buffer} = parse_ndjson(state.buffer, data)
        normalized = Enum.map(events, &normalize_event/1)
        done = Enum.any?(normalized, &match?({:done, _}, &1))
        {normalized, %{state | buffer: new_buffer, done: done}}

      {:ollama_stream_end, ref} when ref == state.ref ->
        final_events = flush_buffer(state.buffer)
        {final_events, %{state | buffer: "", done: true}}

      {:ollama_stream_error, ref, reason} when ref == state.ref ->
        {:halt, %{state | done: true, error: reason}}
    after
      state.timeout ->
        {:halt, %{state | done: true}}
    end
  end

  defp cleanup_stream(%{pid: pid}) do
    Process.exit(pid, :kill)
    :ok
  end

  defp flush_buffer(""), do: []

  defp flush_buffer(buffer) do
    case Jason.decode(buffer) do
      {:ok, event} -> [normalize_event(event)]
      {:error, _} -> []
    end
  end

  # -- Private: Parsing --

  @doc false
  def parse_ndjson(buffer, new_data) do
    combined = buffer <> new_data
    lines = String.split(combined, "\n")
    {complete, [remainder]} = Enum.split(lines, -1)

    events =
      complete
      |> Enum.reject(&(&1 == ""))
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, event} -> [event]
          {:error, _} -> []
        end
      end)

    {events, remainder}
  end

  @doc false
  def normalize_event(%{"done" => false, "message" => %{"content" => text}}) do
    {:text_delta, text}
  end

  def normalize_event(%{"done" => true} = event) do
    message = Map.get(event, "message", %{})
    tool_calls = Map.get(message, "tool_calls") || []

    {:done,
     %{
       content: Map.get(message, "content", ""),
       tool_calls: tool_calls,
       usage: %{
         prompt_tokens: Map.get(event, "prompt_eval_count"),
         completion_tokens: Map.get(event, "eval_count")
       }
     }}
  end

  def normalize_event(_event), do: {:text_delta, ""}

  defp parse_chat_response(body) do
    message = Map.get(body, "message", %{})
    tool_calls = Map.get(message, "tool_calls") || []

    %{
      content: Map.get(message, "content", ""),
      tool_calls: tool_calls,
      usage: %{
        prompt_tokens: Map.get(body, "prompt_eval_count"),
        completion_tokens: Map.get(body, "eval_count")
      }
    }
  end

  # -- Private: Request building --

  defp build_chat_body(messages, opts, stream) do
    body = %{
      model: chat_model(opts),
      messages: normalize_messages(messages),
      stream: stream
    }

    case Keyword.get(opts, :options) do
      nil -> body
      options -> Map.put(body, :options, options)
    end
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(Map.get(msg, :role, Map.get(msg, "role", "user"))),
        "content" => to_string(Map.get(msg, :content, Map.get(msg, "content", "")))
      }
    end)
  end

  # -- Private: Config --

  defp base_url do
    config = Application.get_env(:familiar, :ollama, [])
    Keyword.get(config, :base_url, @default_base_url)
  end

  defp chat_model(opts) do
    Keyword.get_lazy(opts, :model, fn ->
      config = Application.get_env(:familiar, :ollama, [])
      Keyword.get(config, :chat_model, "llama3.2")
    end)
  end

  defp receive_timeout(opts) do
    Keyword.get_lazy(opts, :receive_timeout, fn ->
      config = Application.get_env(:familiar, :ollama, [])
      Keyword.get(config, :receive_timeout, @default_receive_timeout)
    end)
  end
end
