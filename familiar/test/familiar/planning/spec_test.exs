defmodule Familiar.Planning.SpecTest do
  use Familiar.DataCase, async: true

  alias Familiar.Planning.Session
  alias Familiar.Planning.Spec

  setup do
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{description: "test feature"})
      |> Repo.insert()

    %{session: session}
  end

  describe "changeset/2" do
    test "valid attrs create a valid changeset", %{session: session} do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: session.id,
          title: "Add User Accounts",
          body: "# Add User Accounts\n\nSpec body here."
        })

      assert changeset.valid?
    end

    test "requires session_id, title, and body" do
      changeset = Spec.changeset(%Spec{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:session_id]
      assert errors[:title]
      assert errors[:body]
    end

    test "defaults status to draft", %{session: session} do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: session.id,
          title: "Test",
          body: "Body"
        })

      assert get_field(changeset, :status) == "draft"
    end

    test "validates status inclusion", %{session: session} do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: session.id,
          title: "Test",
          body: "Body",
          status: "invalid"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid statuses", %{session: session} do
      for status <- Spec.valid_statuses() do
        changeset =
          Spec.changeset(%Spec{}, %{
            session_id: session.id,
            title: "Test",
            body: "Body",
            status: status
          })

        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "validates metadata is valid JSON object", %{session: session} do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: session.id,
          title: "Test",
          body: "Body",
          metadata: "not json"
        })

      refute changeset.valid?
      assert %{metadata: ["must be valid JSON"]} = errors_on(changeset)
    end

    test "rejects metadata that is not a JSON object", %{session: session} do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: session.id,
          title: "Test",
          body: "Body",
          metadata: "[1,2,3]"
        })

      refute changeset.valid?
      assert %{metadata: ["must be a JSON object"]} = errors_on(changeset)
    end
  end

  describe "persistence" do
    test "inserts and retrieves a spec", %{session: session} do
      {:ok, spec} =
        %Spec{}
        |> Spec.changeset(%{
          session_id: session.id,
          title: "Add Auth",
          body: "# Add Auth\n\nSpec body.",
          metadata: ~s({"verified": 3, "unverified": 1})
        })
        |> Repo.insert()

      assert spec.id
      assert spec.title == "Add Auth"
      assert spec.status == "draft"
      assert spec.session_id == session.id
    end

    test "enforces foreign key constraint" do
      changeset =
        Spec.changeset(%Spec{}, %{
          session_id: 999_999,
          title: "Test",
          body: "Body"
        })

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(changeset)
      end
    end

    test "cascade deletes specs when session is deleted", %{session: session} do
      {:ok, _spec} =
        %Spec{}
        |> Spec.changeset(%{session_id: session.id, title: "T", body: "B"})
        |> Repo.insert()

      Repo.delete!(session)
      assert [] == Repo.all(Spec)
    end
  end
end
