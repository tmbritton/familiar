defmodule Familiar.Planning.SessionTest do
  use Familiar.DataCase, async: true

  alias Familiar.Planning.Session

  describe "changeset/2" do
    test "valid attrs create a valid changeset" do
      changeset = Session.changeset(%Session{}, %{description: "add user accounts"})
      assert changeset.valid?
    end

    test "description is required" do
      changeset = Session.changeset(%Session{}, %{})
      refute changeset.valid?
      assert %{description: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects empty string description" do
      changeset = Session.changeset(%Session{}, %{description: ""})
      refute changeset.valid?
    end

    test "rejects overly long description" do
      long = String.duplicate("a", 4001)
      changeset = Session.changeset(%Session{}, %{description: long})
      refute changeset.valid?
      assert %{description: [msg]} = errors_on(changeset)
      assert msg =~ "at most"
    end

    test "accepts context field" do
      changeset = Session.changeset(%Session{}, %{description: "test", context: "project context"})
      assert changeset.valid?
      assert get_field(changeset, :context) == "project context"
    end

    test "defaults status to active" do
      changeset = Session.changeset(%Session{}, %{description: "test"})
      assert get_field(changeset, :status) == "active"
    end

    test "validates status inclusion" do
      changeset = Session.changeset(%Session{}, %{description: "test", status: "invalid"})
      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid statuses" do
      for status <- Session.valid_statuses() do
        changeset = Session.changeset(%Session{}, %{description: "test", status: status})
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end
  end

  describe "persistence" do
    test "inserts and retrieves a session" do
      {:ok, session} =
        %Session{}
        |> Session.changeset(%{description: "add user accounts"})
        |> Repo.insert()

      assert session.id
      assert session.description == "add user accounts"
      assert session.status == "active"
      assert session.inserted_at
      assert session.updated_at
    end
  end
end
