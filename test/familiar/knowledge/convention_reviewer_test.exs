defmodule Familiar.Knowledge.ConventionReviewerTest do
  use Familiar.DataCase, async: false

  alias Familiar.Knowledge.ConventionReviewer
  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  describe "review/2" do
    test "accept all marks all conventions as reviewed" do
      entries = insert_test_conventions(3)

      {:ok, result} = ConventionReviewer.review(entries, io_opts(["a"]))

      assert result.accepted == 3
      assert result.rejected == 0

      for entry <- entries do
        db_entry = Repo.get!(Entry, entry.id)
        meta = Jason.decode!(db_entry.metadata)
        assert meta["reviewed"] == true
      end
    end

    test "reject removes convention from database" do
      entries = insert_test_conventions(1)

      {:ok, result} = ConventionReviewer.review(entries, io_opts(["r", "r"]))

      assert result.rejected == 1
      assert Repo.get(Entry, hd(entries).id) == nil
    end

    test "edit updates convention text" do
      entries = insert_test_conventions(1)

      {:ok, result} =
        ConventionReviewer.review(entries, io_opts(["r", "e", "Updated convention text"]))

      assert result.edited == 1
      updated = Repo.get!(Entry, hd(entries).id)
      assert updated.text == "Updated convention text"
    end

    test "skip leaves conventions as-is" do
      entries = insert_test_conventions(2)

      {:ok, result} = ConventionReviewer.review(entries, io_opts(["s"]))

      assert result.accepted == 2
    end

    test "returns zero counts for empty list" do
      {:ok, result} = ConventionReviewer.review([])
      assert result == %{accepted: 0, rejected: 0, edited: 0}
    end
  end

  # -- Test Helpers --

  defp insert_test_conventions(count) do
    for i <- 1..count do
      {:ok, entry} =
        Repo.insert(%Entry{
          text: "Convention #{i}: uses pattern #{i}",
          type: "convention",
          source: "init_scan",
          metadata:
            Jason.encode!(%{
              evidence_count: 10 + i,
              evidence_total: 15,
              evidence_ratio: 0.8,
              reviewed: false
            })
        })

      %{
        id: entry.id,
        text: entry.text,
        evidence_count: 10 + i,
        evidence_total: 15,
        reviewed: false
      }
    end
  end

  defp io_opts(responses) do
    {:ok, agent} = Agent.start_link(fn -> responses end)

    gets_fn = fn _prompt ->
      Agent.get_and_update(agent, fn
        [head | tail] -> {head, tail}
        [] -> {"\n", []}
      end)
    end

    [puts_fn: fn _msg -> :ok end, gets_fn: gets_fn]
  end
end
