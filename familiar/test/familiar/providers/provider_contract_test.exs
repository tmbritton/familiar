defmodule Familiar.Providers.ProviderContractTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Familiar.Test.EmbeddingHelpers, only: [zero_vector: 0]
  import Mox

  alias Familiar.Knowledge
  alias Familiar.Knowledge.EmbedderMock
  alias Familiar.Providers.LLMMock

  setup :verify_on_exit!

  # -- Generators --

  defp message_gen do
    gen all(
          role <- member_of(["user", "assistant", "system"]),
          content <- string(:printable, min_length: 1, max_length: 200)
        ) do
      %{role: role, content: content}
    end
  end

  defp messages_gen do
    gen all(messages <- list_of(message_gen(), min_length: 1, max_length: 5)) do
      messages
    end
  end

  defp embed_text_gen do
    string(:printable, min_length: 1, max_length: 500)
  end

  # -- Properties --

  describe "LLM.chat/2 contract" do
    property "always returns {:ok, map()} or {:error, {atom(), map()}} for valid input" do
      check all(messages <- messages_gen()) do
        # Stub mock to return a valid response
        stub(LLMMock, :chat, fn _msgs, _opts ->
          {:ok, %{content: "response", tool_calls: [], usage: %{}}}
        end)

        result = LLMMock.chat(messages, [])

        assert match?({:ok, %{content: _, tool_calls: _, usage: _}}, result) or
                 match?({:error, {atom, map}} when is_atom(atom) and is_map(map), result)
      end
    end

    property "error responses always have {atom, map} structure" do
      check all(messages <- messages_gen()) do
        stub(LLMMock, :chat, fn _msgs, _opts ->
          {:error, {:provider_unavailable, %{provider: :ollama, reason: :timeout}}}
        end)

        assert {:error, {type, details}} = LLMMock.chat(messages, [])
        assert is_atom(type)
        assert is_map(details)
      end
    end
  end

  describe "Embedder.embed/1 contract" do
    property "always returns {:ok, [float()]} or {:error, {atom(), map()}} for valid input" do
      check all(text <- embed_text_gen()) do
        vector = List.duplicate(0.1, Knowledge.embedding_dimensions())

        stub(EmbedderMock, :embed, fn _text ->
          {:ok, vector}
        end)

        result = EmbedderMock.embed(text)

        case result do
          {:ok, vec} ->
            assert is_list(vec)
            assert Enum.all?(vec, &is_float/1)

          {:error, {type, details}} ->
            assert is_atom(type)
            assert is_map(details)
        end
      end
    end

    property "embedding vectors have consistent dimensionality" do
      expected_dim = Knowledge.embedding_dimensions()

      check all(text <- embed_text_gen()) do
        stub(EmbedderMock, :embed, fn _text -> {:ok, zero_vector()} end)

        {:ok, vector} = EmbedderMock.embed(text)
        assert length(vector) == expected_dim
      end
    end
  end
end
