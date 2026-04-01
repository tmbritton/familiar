defmodule Familiar.Knowledge.EmbedderTest do
  use Familiar.MockCase

  alias Familiar.Knowledge.EmbedderMock

  describe "Embedder behaviour mock" do
    test "embed/1 can return deterministic vectors" do
      expect(EmbedderMock, :embed, fn text ->
        assert "Handler files follow snake_case naming" = text
        {:ok, [0.1, 0.2, 0.3, 0.4]}
      end)

      assert {:ok, [0.1, 0.2, 0.3, 0.4]} =
               EmbedderMock.embed("Handler files follow snake_case naming")
    end

    test "embed/1 can return error tuples" do
      expect(EmbedderMock, :embed, fn _text ->
        {:error, {:provider_unavailable, %{provider: :ollama}}}
      end)

      assert {:error, {:provider_unavailable, _}} = EmbedderMock.embed("any text")
    end
  end
end
