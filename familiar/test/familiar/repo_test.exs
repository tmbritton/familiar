defmodule Familiar.RepoTest do
  use Familiar.DataCase, async: false

  alias Familiar.Repo

  describe "sqlite-vec extension" do
    test "vec0 extension is loaded and functional" do
      # Verify the extension loaded by querying its version
      {:ok, %{rows: [[version]]}} = Repo.query("SELECT vec_version()")
      assert is_binary(version)
    end

    test "can insert and retrieve vectors by cosine similarity" do
      # Insert test vectors as JSON arrays
      Repo.query!("INSERT INTO vec_test(rowid, embedding) VALUES (1, ?)", ["[1.0, 0.0, 0.0]"])
      Repo.query!("INSERT INTO vec_test(rowid, embedding) VALUES (2, ?)", ["[0.0, 1.0, 0.0]"])
      Repo.query!("INSERT INTO vec_test(rowid, embedding) VALUES (3, ?)", ["[0.9, 0.1, 0.0]"])

      # Query by cosine similarity to [1.0, 0.0, 0.0] — should return vec1 first, vec3 second
      {:ok, %{rows: rows}} =
        Repo.query(
          "SELECT rowid, distance FROM vec_test WHERE embedding MATCH ? ORDER BY distance LIMIT 3",
          ["[1.0, 0.0, 0.0]"]
        )

      # First result should be rowid 1 (exact match, distance 0)
      assert [[1, dist1], [3, dist3], [2, _dist2]] = rows
      assert dist1 < dist3
    end

    test "cosine similarity returns ranked results" do
      # Clear any previous test data
      Repo.query!("DELETE FROM vec_test")

      # Insert vectors with known similarity relationships
      Repo.query!("INSERT INTO vec_test(rowid, embedding) VALUES (10, ?)", ["[0.8, 0.2, 0.0]"])
      Repo.query!("INSERT INTO vec_test(rowid, embedding) VALUES (20, ?)", ["[0.0, 0.0, 1.0]"])

      {:ok, %{rows: rows}} =
        Repo.query(
          "SELECT rowid, distance FROM vec_test WHERE embedding MATCH ? ORDER BY distance LIMIT 2",
          ["[1.0, 0.0, 0.0]"]
        )

      # Similar vector should rank before orthogonal
      assert [[10, _], [20, _]] = rows
    end
  end
end
