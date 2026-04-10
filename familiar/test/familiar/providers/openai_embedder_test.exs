defmodule Familiar.Providers.OpenAIEmbedderTest do
  use ExUnit.Case, async: false

  alias Familiar.Providers.OpenAIEmbedder

  # All tests run async: false because they manipulate Application env
  # and system env vars. The embed/1 happy path is covered via the
  # parse_response/1 contract tests below — exercising the full HTTP
  # round trip would require mocking Req, which adds dependency surface
  # without catching bugs the parse tests don't already catch.

  describe "parse_response/1 — success" do
    test "extracts first embedding from data array" do
      vector = [0.1, 0.2, 0.3]

      response =
        {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => vector}]}}}

      assert {:ok, ^vector} = OpenAIEmbedder.parse_response(response)
    end

    test "takes first embedding when the API returns multiple" do
      v1 = [1.0, 0.0]
      v2 = [0.0, 1.0]

      response =
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => [%{"embedding" => v1}, %{"embedding" => v2}]}
         }}

      assert {:ok, ^v1} = OpenAIEmbedder.parse_response(response)
    end
  end

  describe "parse_response/1 — malformed success body" do
    test "returns :unexpected_body when data array is missing" do
      response = {:ok, %Req.Response{status: 200, body: %{"foo" => "bar"}}}

      assert {:error,
              {:provider_unavailable, %{provider: :openai_compatible, reason: :unexpected_body}}} =
               OpenAIEmbedder.parse_response(response)
    end

    test "returns :unexpected_body when data array is empty" do
      response = {:ok, %Req.Response{status: 200, body: %{"data" => []}}}

      assert {:error,
              {:provider_unavailable, %{provider: :openai_compatible, reason: :unexpected_body}}} =
               OpenAIEmbedder.parse_response(response)
    end
  end

  describe "parse_response/1 — HTTP errors" do
    test "401 returns :unauthorized" do
      response = {:ok, %Req.Response{status: 401, body: %{"error" => "invalid key"}}}

      assert {:error,
              {:provider_unavailable, %{provider: :openai_compatible, reason: :unauthorized}}} =
               OpenAIEmbedder.parse_response(response)
    end

    test "404 returns :model_not_found" do
      response = {:ok, %Req.Response{status: 404, body: "model missing"}}

      assert {:error,
              {:provider_unavailable, %{provider: :openai_compatible, reason: :model_not_found}}} =
               OpenAIEmbedder.parse_response(response)
    end

    test "500 returns :api_error with status and body" do
      response = {:ok, %Req.Response{status: 500, body: "internal"}}

      assert {:error,
              {:provider_unavailable,
               %{
                 provider: :openai_compatible,
                 reason: :api_error,
                 status: 500,
                 body: "internal"
               }}} = OpenAIEmbedder.parse_response(response)
    end
  end

  describe "parse_response/1 — transport errors" do
    test "connection refused" do
      response = {:error, %Req.TransportError{reason: :econnrefused}}

      assert {:error,
              {:provider_unavailable,
               %{provider: :openai_compatible, reason: :connection_refused}}} =
               OpenAIEmbedder.parse_response(response)
    end

    test "timeout" do
      response = {:error, %Req.TransportError{reason: :timeout}}

      assert {:error, {:provider_unavailable, %{provider: :openai_compatible, reason: :timeout}}} =
               OpenAIEmbedder.parse_response(response)
    end

    test "unknown transport error preserves reason" do
      response = {:error, %Req.TransportError{reason: :nxdomain}}

      assert {:error,
              {:provider_unavailable,
               %{provider: :openai_compatible, reason: %Req.TransportError{}}}} =
               OpenAIEmbedder.parse_response(response)
    end
  end

  describe "embed/1 — config validation" do
    setup do
      # Snapshot and clear env vars / app config so the tests start from a
      # known empty state. Restore everything on exit.
      prev_env = %{
        api_key: System.get_env("FAMILIAR_API_KEY"),
        base_url: System.get_env("FAMILIAR_BASE_URL"),
        embedding_model: System.get_env("FAMILIAR_EMBEDDING_MODEL"),
        project_dir: System.get_env("FAMILIAR_PROJECT_DIR")
      }

      prev_app = Application.get_env(:familiar, :openai_compatible, [])

      # Point at a tmp dir that has NO config.toml so project_config returns
      # nothing. This ensures only app config + env vars feed resolution.
      tmp_dir =
        Path.join(System.tmp_dir!(), "openai_embedder_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      System.put_env("FAMILIAR_PROJECT_DIR", tmp_dir)
      System.delete_env("FAMILIAR_API_KEY")
      System.delete_env("FAMILIAR_BASE_URL")
      System.delete_env("FAMILIAR_EMBEDDING_MODEL")
      Application.delete_env(:familiar, :openai_compatible)

      on_exit(fn ->
        restore_env("FAMILIAR_API_KEY", prev_env.api_key)
        restore_env("FAMILIAR_BASE_URL", prev_env.base_url)
        restore_env("FAMILIAR_EMBEDDING_MODEL", prev_env.embedding_model)
        restore_env("FAMILIAR_PROJECT_DIR", prev_env.project_dir)
        Application.put_env(:familiar, :openai_compatible, prev_app)
        File.rm_rf!(tmp_dir)
      end)

      :ok
    end

    test "returns :missing_api_key when no api key is configured" do
      assert {:error,
              {:provider_unavailable, %{provider: :openai_compatible, reason: :missing_api_key}}} =
               OpenAIEmbedder.embed("anything")
    end

    test "returns :missing_embedding_model when embedding_model is explicitly empty string" do
      System.put_env("FAMILIAR_API_KEY", "sk-fake")
      System.put_env("FAMILIAR_EMBEDDING_MODEL", "")

      assert {:error,
              {:provider_unavailable,
               %{provider: :openai_compatible, reason: :missing_embedding_model}}} =
               OpenAIEmbedder.embed("anything")
    end

    test "returns :missing_embedding_model when embedding_model is nil (not configured)" do
      # AC1: the nil path must surface the explicit error — NOT silently
      # default to text-embedding-3-small. Guards against a footgun where
      # a user exports only FAMILIAR_API_KEY without configuring a model
      # and silently gets an unexpected default.
      System.put_env("FAMILIAR_API_KEY", "sk-fake")
      # FAMILIAR_EMBEDDING_MODEL intentionally not set; app config is empty.

      assert {:error,
              {:provider_unavailable,
               %{provider: :openai_compatible, reason: :missing_embedding_model}}} =
               OpenAIEmbedder.embed("anything")
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
