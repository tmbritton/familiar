defmodule Familiar.ApplicationDriftTest do
  @moduledoc """
  Story 7.5-7 drift detection branches — ensures
  `Familiar.Application.do_check_embedding_drift/0` logs the expected
  warnings for `:model_changed` and `:model_unset` and stays silent on
  `:ok`. Uses `reset_drift_sentinel/0` to exercise the warning path
  multiple times in the same VM (the production `check_embedding_drift/0`
  skips on the sentinel, which matters for a single-shot boot path but
  would make these tests one-shot otherwise).
  """

  use Familiar.DataCase, async: false

  import ExUnit.CaptureLog

  alias Familiar.Application, as: FamApp
  alias Familiar.Knowledge.EmbeddingMetadata
  alias Familiar.Knowledge.EmbeddingMetadataRow
  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  setup do
    # Reset singleton row + entries so every test starts from a known
    # clean-install baseline.
    Repo.update_all(EmbeddingMetadataRow, set: [model_name: nil, dimensions: nil])
    Repo.delete_all(Entry)
    Repo.query!("DELETE FROM knowledge_entry_embeddings")

    # Snapshot the configured model so each test can override it.
    prev_app = Application.get_env(:familiar, :openai_compatible, [])

    on_exit(fn ->
      Application.put_env(:familiar, :openai_compatible, prev_app)
      FamApp.reset_drift_sentinel()
    end)

    FamApp.reset_drift_sentinel()
    :ok
  end

  defp put_configured_model(model) do
    prev = Application.get_env(:familiar, :openai_compatible, [])
    Application.put_env(:familiar, :openai_compatible, Keyword.put(prev, :embedding_model, model))
  end

  describe "do_check_embedding_drift/0" do
    test "is silent when stored matches configured" do
      {:ok, _} = EmbeddingMetadata.set("text-embedding-3-small", 1536)
      put_configured_model("text-embedding-3-small")

      log = capture_log(fn -> FamApp.do_check_embedding_drift() end)

      refute log =~ "Embedding model changed"
      refute log =~ "not recorded"
    end

    test "is silent on clean install (no metadata, no entries)" do
      put_configured_model("text-embedding-3-small")

      log = capture_log(fn -> FamApp.do_check_embedding_drift() end)

      refute log =~ "Embedding model"
    end

    test "warns :model_unset when metadata is empty but entries exist" do
      put_configured_model("text-embedding-3-small")

      {:ok, _} =
        Repo.insert(%Entry{
          text: "old entry from before metadata existed",
          type: "fact",
          source: "manual"
        })

      log = capture_log(fn -> FamApp.do_check_embedding_drift() end)

      assert log =~ "Embedding model is not recorded"
      assert log =~ "stored=unset"
      assert log =~ "configured=text-embedding-3-small"
      assert log =~ "fam context --reindex"
    end

    test "warns :model_changed when stored differs from configured" do
      {:ok, _} = EmbeddingMetadata.set("nomic-embed-text", 768)
      put_configured_model("text-embedding-3-small")

      log = capture_log(fn -> FamApp.do_check_embedding_drift() end)

      assert log =~ "Embedding model changed"
      assert log =~ "stored=nomic-embed-text"
      assert log =~ "configured=text-embedding-3-small"
      assert log =~ "fam context --reindex"
    end

    test "is silent when no configured model (nothing to compare)" do
      Application.put_env(:familiar, :openai_compatible, [])

      log = capture_log(fn -> FamApp.do_check_embedding_drift() end)

      refute log =~ "Embedding model"
    end
  end

  describe "reset_drift_sentinel/0" do
    test "clears the persistent_term flag so the warning can fire again" do
      {:ok, _} = EmbeddingMetadata.set("nomic-embed-text", 768)
      put_configured_model("text-embedding-3-small")

      first = capture_log(fn -> FamApp.do_check_embedding_drift() end)
      assert first =~ "Embedding model changed"

      # Without reset, the sentinel now blocks the production
      # check_embedding_drift/0 path. do_check_embedding_drift/0 itself
      # does not consult the sentinel (it just sets it), so calling it
      # directly fires the warning again — but the sentinel is set.
      assert :persistent_term.get({FamApp, :drift_warned}, false) == true

      FamApp.reset_drift_sentinel()
      assert :persistent_term.get({FamApp, :drift_warned}, false) == false
    end

    test "is idempotent when the sentinel was never set" do
      FamApp.reset_drift_sentinel()
      FamApp.reset_drift_sentinel()
      assert :persistent_term.get({FamApp, :drift_warned}, false) == false
    end
  end
end
