defmodule Familiar.Providers.StreamEvent do
  @moduledoc """
  Common stream event type definitions for LLM provider responses.

  All provider adapters normalize their streaming responses to these
  event types. Consumers (planning engine, agent runner, Phoenix Channel)
  work exclusively with this common format.
  """

  @type t ::
          {:text_delta, binary()}
          | {:tool_call_delta, map()}
          | {:tool_result, map()}
          | {:done, done_payload()}

  @type done_payload :: %{
          content: binary(),
          tool_calls: [map()],
          usage: usage()
        }

  @type usage :: %{
          optional(:prompt_tokens) => non_neg_integer() | nil,
          optional(:completion_tokens) => non_neg_integer() | nil
        }
end
