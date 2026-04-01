defmodule Familiar.Providers.LLM do
  @moduledoc """
  Behaviour for LLM provider adapters.

  Implementations translate between Familiar's common interface and
  provider-specific APIs (Ollama, Anthropic). Streaming responses are
  normalized to a common event format.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type chat_opts :: keyword()
  @type stream_event ::
          {:text_delta, binary()}
          | {:tool_call_delta, map()}
          | {:tool_result, map()}
          | {:done, %{content: binary(), tool_calls: list(), usage: map()}}

  @doc "Send a chat request and return the complete response."
  @callback chat(messages :: [message()], opts :: chat_opts()) ::
              {:ok, map()} | {:error, {atom(), map()}}

  @doc "Send a chat request and stream response events to the caller."
  @callback stream_chat(messages :: [message()], opts :: chat_opts()) ::
              {:ok, Enumerable.t()} | {:error, {atom(), map()}}
end
