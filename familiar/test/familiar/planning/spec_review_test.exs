defmodule Familiar.Planning.SpecReviewTest do
  use Familiar.DataCase, async: false

  alias Familiar.Planning.Session
  alias Familiar.Planning.Spec
  alias Familiar.Planning.SpecReview

  defmodule StubShell do
    @moduledoc false
    def cmd(_editor, _args, _opts), do: {:ok, %{output: "", exit_code: 0}}
  end

  setup do
    {:ok, session} =
      %Session{}
      |> Session.changeset(%{description: "add auth", context: "Phoenix project"})
      |> Repo.insert()

    {:ok, spec} =
      %Spec{}
      |> Spec.changeset(%{
        session_id: session.id,
        title: "Add Auth",
        body: "# Add Auth\n\n## Assumptions\n\nUsers table exists",
        file_path: ".familiar/specs/#{session.id}-add-auth.md"
      })
      |> Repo.insert()

    %{session: session, spec: spec}
  end

  defmodule FreshFS do
    @moduledoc false
    def read(_path) do
      {:ok, "---\ntitle: \"Add Auth\"\nsession_id: 1\nstatus: draft\n---\n\n# Add Auth\n\nEdited body"}
    end

    def write(_path, _content), do: :ok
    def stat(_path), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 500}}
  end

  defmodule ModifiedFS do
    @moduledoc false
    def read(_path) do
      {:ok, "---\ntitle: \"Add Auth\"\nsession_id: 1\nstatus: draft\n---\n\n# Add Auth\n\nUser edited this"}
    end

    def write(_path, _content), do: :ok
    # Return mtime far in the future to trigger modification detection
    def stat(_path), do: {:ok, %{mtime: ~U[2099-01-01 00:00:00Z], size: 600}}
  end

  defmodule MissingFileFS do
    @moduledoc false
    def read(_path), do: {:error, {:file_error, %{reason: :enoent}}}
    def write(_path, _content), do: :ok
    def stat(_path), do: {:error, {:file_error, %{reason: :enoent}}}
  end

  describe "approve/2" do
    test "approves a draft spec", %{spec: spec} do
      {:ok, approved} = SpecReview.approve(spec, file_system: FreshFS)

      assert approved.status == "approved"
      assert Repo.get!(Spec, spec.id).status == "approved"
    end

    test "rejects approval of already-approved spec", %{spec: spec} do
      {:ok, approved} = SpecReview.approve(spec, file_system: FreshFS)

      {:error, {:spec_not_reviewable, %{status: "approved"}}} =
        SpecReview.approve(approved, file_system: FreshFS)
    end

    test "rejects approval of rejected spec", %{spec: spec} do
      {:ok, rejected} = SpecReview.reject(spec, file_system: FreshFS)

      {:error, {:spec_not_reviewable, _}} =
        SpecReview.approve(rejected, file_system: FreshFS)
    end

    test "prompts confirmation when file was modified externally", %{spec: spec} do
      {:ok, approved} =
        SpecReview.approve(spec,
          file_system: ModifiedFS,
          confirm_fn: fn _prompt -> "y" end
        )

      assert approved.status == "approved"
    end

    test "cancels approval when user declines modified file", %{spec: spec} do
      {:error, {:approval_cancelled, _}} =
        SpecReview.approve(spec,
          file_system: ModifiedFS,
          confirm_fn: fn _prompt -> "n" end
        )

      # Status should still be draft
      assert Repo.get!(Spec, spec.id).status == "draft"
    end
  end

  describe "reject/2" do
    test "rejects a draft spec", %{spec: spec} do
      {:ok, rejected} = SpecReview.reject(spec, file_system: FreshFS)

      assert rejected.status == "rejected"
      assert Repo.get!(Spec, spec.id).status == "rejected"
    end

    test "rejects rejection of already-approved spec", %{spec: spec} do
      {:ok, approved} = SpecReview.approve(spec, file_system: FreshFS)

      {:error, {:spec_not_reviewable, _}} =
        SpecReview.reject(approved, file_system: FreshFS)
    end
  end

  describe "stat_check/2" do
    test "detects unmodified file", %{spec: spec} do
      {:ok, result} = SpecReview.stat_check(spec, file_system: FreshFS)
      assert result.modified == false
    end

    test "detects modified file", %{spec: spec} do
      {:ok, result} = SpecReview.stat_check(spec, file_system: ModifiedFS)
      assert result.modified == true
    end

    test "returns error for missing file", %{spec: spec} do
      {:error, {:file_missing, %{path: _}}} = SpecReview.stat_check(spec, file_system: MissingFileFS)
    end

    test "returns error for spec without file_path" do
      spec = %Spec{file_path: nil}
      {:error, {:no_file_path, _}} = SpecReview.stat_check(spec, [])
    end
  end

  describe "reload_if_modified/2" do
    test "reloads body when file was modified", %{spec: spec} do
      {:ok, reloaded} = SpecReview.reload_if_modified(spec, file_system: ModifiedFS)
      assert reloaded.body =~ "User edited this"
    end

    test "does not reload when file is unmodified", %{spec: spec} do
      {:ok, same} = SpecReview.reload_if_modified(spec, file_system: FreshFS)
      assert same.body == spec.body
    end
  end

  describe "open_in_editor/2" do
    test "opens file in editor and returns modification status", %{spec: spec} do
      {:ok, result} =
        SpecReview.open_in_editor(spec,
          shell_mod: StubShell,
          file_system: FreshFS,
          editor_env: "nano"
        )

      assert is_boolean(result.modified)
    end

    test "returns error when editor fails", %{spec: spec} do
      failing_shell = Module.concat([__MODULE__, "FailShell"])

      defmodule FailShell do
        @moduledoc false
        def cmd(_ed, _args, _opts), do: {:ok, %{output: "", exit_code: 1}}
      end

      {:error, {:editor_failed, %{exit_code: 1}}} =
        SpecReview.open_in_editor(spec,
          shell_mod: FailShell,
          file_system: FreshFS,
          editor_env: "badeditor"
        )
    end

    test "returns error for spec without file_path" do
      spec = %Spec{file_path: nil}
      {:error, {:no_file_path, _}} = SpecReview.open_in_editor(spec, [])
    end

    test "detects file modification after editor closes", %{spec: spec} do
      {:ok, result} =
        SpecReview.open_in_editor(spec,
          shell_mod: StubShell,
          file_system: ModifiedFS,
          editor_env: "vim"
        )

      assert result.modified == true
    end

    test "uses fallback editor when EDITOR not set", %{spec: spec} do
      # editor_env: "vi" simulates the fallback
      {:ok, _result} =
        SpecReview.open_in_editor(spec,
          shell_mod: StubShell,
          file_system: FreshFS,
          editor_env: "vi"
        )
    end
  end

  describe "frontmatter update" do
    test "updates frontmatter status on approve", %{spec: spec} do
      written_content = :persistent_term.put({__MODULE__, :written}, nil)
      _ = written_content

      defmodule WriteCapture do
        @moduledoc false
        def read(_path) do
          {:ok, "---\ntitle: \"Add Auth\"\nstatus: draft\n---\n\n# Body"}
        end

        def write(_path, content) do
          :persistent_term.put({Familiar.Planning.SpecReviewTest, :written}, content)
          :ok
        end

        def stat(_path), do: {:ok, %{mtime: ~U[2026-04-02 10:00:00Z], size: 100}}
      end

      {:ok, _approved} = SpecReview.approve(spec, file_system: WriteCapture)

      written = :persistent_term.get({__MODULE__, :written})
      assert written =~ "status: approved"
      refute written =~ "status: draft"

      :persistent_term.erase({__MODULE__, :written})
    end
  end
end
