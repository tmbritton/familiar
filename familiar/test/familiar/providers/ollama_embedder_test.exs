defmodule Familiar.Providers.OllamaEmbedderTest do
  use ExUnit.Case, async: true

  alias Familiar.Providers.OllamaEmbedder

  describe "parse_response/1" do
    test "extracts vector from successful embedding response" do
      vector = List.duplicate(0.1, 768)
      response = {:ok, %Req.Response{status: 200, body: %{"embeddings" => [vector]}}}

      assert {:ok, ^vector} = OllamaEmbedder.parse_response(response)
    end

    test "takes first vector when multiple embeddings returned" do
      v1 = List.duplicate(0.1, 768)
      v2 = List.duplicate(0.2, 768)
      response = {:ok, %Req.Response{status: 200, body: %{"embeddings" => [v1, v2]}}}

      assert {:ok, ^v1} = OllamaEmbedder.parse_response(response)
    end

    test "returns error for empty embeddings" do
      response = {:ok, %Req.Response{status: 200, body: %{"embeddings" => []}}}

      assert {:error, {:provider_unavailable, %{reason: :empty_embedding}}} =
               OllamaEmbedder.parse_response(response)
    end

    test "returns error for 404 (model not found)" do
      response = {:ok, %Req.Response{status: 404, body: "model not found"}}

      assert {:error, {:provider_unavailable, %{reason: :model_not_found}}} =
               OllamaEmbedder.parse_response(response)
    end

    test "returns error for unexpected status" do
      response = {:ok, %Req.Response{status: 500, body: "internal error"}}

      assert {:error, {:provider_unavailable, %{reason: :api_error, status: 500}}} =
               OllamaEmbedder.parse_response(response)
    end

    test "returns error for connection refused" do
      response = {:error, %Req.TransportError{reason: :econnrefused}}

      assert {:error, {:provider_unavailable, %{reason: :connection_refused}}} =
               OllamaEmbedder.parse_response(response)
    end

    test "returns error for timeout" do
      response = {:error, %Req.TransportError{reason: :timeout}}

      assert {:error, {:provider_unavailable, %{reason: :timeout}}} =
               OllamaEmbedder.parse_response(response)
    end

    test "returns error for unknown transport error" do
      response = {:error, %Req.TransportError{reason: :nxdomain}}

      assert {:error, {:provider_unavailable, %{reason: %Req.TransportError{}}}} =
               OllamaEmbedder.parse_response(response)
    end
  end
end
