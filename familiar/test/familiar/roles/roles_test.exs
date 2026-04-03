defmodule Familiar.RolesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Familiar.Roles
  alias Familiar.Roles.{Role, Skill}

  @moduletag :tmp_dir

  defp setup_fixture(tmp_dir, type, name, content) do
    dir = Path.join(tmp_dir, type)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "#{name}.md"), content)
  end

  defp valid_role_content do
    """
    ---
    name: coder
    description: A coding agent
    model: sonnet
    lifecycle: session
    skills:
      - implement
      - test
    ---
    You are an expert coder. Write clean, tested code.
    """
  end

  defp valid_skill_content(name \\ "implement") do
    """
    ---
    name: #{name}
    description: Write implementation code
    tools:
      - read_file
      - write_file
    constraints:
      max_files: 10
    ---
    Follow the project conventions and write clean code.
    """
  end

  describe "load_role/2" do
    test "loads a valid role file", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "coder", valid_role_content())

      assert {:ok, %Role{} = role} = Roles.load_role("coder", familiar_dir: tmp_dir)
      assert role.name == "coder"
      assert role.description == "A coding agent"
      assert role.model == "sonnet"
      assert role.lifecycle == :session
      assert role.skills == ["implement", "test"]
      assert role.system_prompt =~ "expert coder"
    end

    test "returns error for non-existent role", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "roles"))

      assert {:error, {:role_not_found, %{name: "nonexistent"}}} =
               Roles.load_role("nonexistent", familiar_dir: tmp_dir)
    end

    test "returns error for malformed frontmatter", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "bad", "no frontmatter here")

      assert {:error, {:invalid_role, %{name: "bad", reason: _}}} =
               Roles.load_role("bad", familiar_dir: tmp_dir)
    end

    test "returns error for missing required fields", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "incomplete", """
      ---
      name: incomplete
      ---
      Just a body.
      """)

      assert {:error, {:invalid_role, %{name: "incomplete", reason: reason}}} =
               Roles.load_role("incomplete", familiar_dir: tmp_dir)

      assert reason =~ "description"
      assert reason =~ "skills"
    end

    test "applies defaults for optional fields", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "minimal", """
      ---
      name: minimal
      description: Minimal role
      skills:
        - basic
      ---
      Do the thing.
      """)

      assert {:ok, %Role{model: "default", lifecycle: :ephemeral}} =
               Roles.load_role("minimal", familiar_dir: tmp_dir)
    end

    test "rejects path traversal in name", %{tmp_dir: tmp_dir} do
      assert {:error, {:invalid_role, %{name: "../etc/passwd", reason: reason}}} =
               Roles.load_role("../etc/passwd", familiar_dir: tmp_dir)

      assert reason =~ "invalid characters"
    end

    test "propagates file read errors", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "unreadable", valid_role_content())
      path = Path.join([tmp_dir, "roles", "unreadable.md"])
      File.chmod!(path, 0o000)

      on_exit(fn -> File.chmod(path, 0o644) end)

      assert {:error, {:file_read_error, _}} =
               Roles.load_role("unreadable", familiar_dir: tmp_dir)
    end
  end

  describe "load_skill/2" do
    test "loads a valid skill file", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "skills", "implement", valid_skill_content())

      assert {:ok, %Skill{} = skill} = Roles.load_skill("implement", familiar_dir: tmp_dir)
      assert skill.name == "implement"
      assert skill.description == "Write implementation code"
      assert skill.tools == ["read_file", "write_file"]
      assert skill.constraints == %{"max_files" => 10}
      assert skill.instructions =~ "project conventions"
    end

    test "returns error for non-existent skill", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "skills"))

      assert {:error, {:skill_not_found, %{name: "nope"}}} =
               Roles.load_skill("nope", familiar_dir: tmp_dir)
    end

    test "defaults constraints to empty map", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "skills", "simple", """
      ---
      name: simple
      description: Simple skill
      tools:
        - read_file
      ---
      Do it.
      """)

      assert {:ok, %Skill{constraints: %{}}} =
               Roles.load_skill("simple", familiar_dir: tmp_dir)
    end

    test "rejects path traversal in name", %{tmp_dir: tmp_dir} do
      assert {:error, {:invalid_skill, %{reason: reason}}} =
               Roles.load_skill("../../etc/passwd", familiar_dir: tmp_dir)

      assert reason =~ "invalid characters"
    end
  end

  describe "list_roles/1" do
    test "lists all valid roles", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "coder", valid_role_content())

      setup_fixture(tmp_dir, "roles", "reviewer", """
      ---
      name: reviewer
      description: Reviews code
      skills:
        - review
      ---
      Review carefully.
      """)

      assert {:ok, roles} = Roles.list_roles(familiar_dir: tmp_dir)
      assert length(roles) == 2
      names = Enum.map(roles, & &1.name) |> Enum.sort()
      assert names == ["coder", "reviewer"]
    end

    test "excludes invalid files with warning", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "good", """
      ---
      name: good
      description: Valid role
      skills:
        - implement
      ---
      Go.
      """)

      setup_fixture(tmp_dir, "roles", "bad", "no frontmatter")

      log =
        capture_log(fn ->
          assert {:ok, roles} = Roles.list_roles(familiar_dir: tmp_dir)
          assert length(roles) == 1
          assert hd(roles).name == "good"
        end)

      assert log =~ "Skipping invalid role file"
    end

    test "returns empty list when no roles directory", %{tmp_dir: tmp_dir} do
      assert {:ok, []} = Roles.list_roles(familiar_dir: tmp_dir)
    end
  end

  describe "list_skills/1" do
    test "lists all valid skills", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "skills", "implement", valid_skill_content("implement"))
      setup_fixture(tmp_dir, "skills", "test", valid_skill_content("test"))

      assert {:ok, skills} = Roles.list_skills(familiar_dir: tmp_dir)
      assert length(skills) == 2
    end

    test "excludes invalid files with warning", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "skills", "good", valid_skill_content("good"))
      setup_fixture(tmp_dir, "skills", "bad", "broken file")

      log =
        capture_log(fn ->
          assert {:ok, skills} = Roles.list_skills(familiar_dir: tmp_dir)
          assert length(skills) == 1
        end)

      assert log =~ "Skipping invalid skill file"
    end
  end

  describe "validate_role/2" do
    test "returns :ok when all skills exist on disk", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "coder", valid_role_content())
      setup_fixture(tmp_dir, "skills", "implement", valid_skill_content("implement"))
      setup_fixture(tmp_dir, "skills", "test", valid_skill_content("test"))

      assert :ok = Roles.validate_role("coder", familiar_dir: tmp_dir)
    end

    test "returns error when referenced skill is missing", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "roles", "coder", valid_role_content())
      setup_fixture(tmp_dir, "skills", "implement", valid_skill_content("implement"))
      # "test" skill is missing

      assert {:error, {:invalid_role, %{name: "coder", reason: reason}}} =
               Roles.validate_role("coder", familiar_dir: tmp_dir)

      assert reason =~ "test"
      assert reason =~ "does not exist"
    end

    test "returns error when role file doesn't exist", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "roles"))

      assert {:error, {:role_not_found, _}} =
               Roles.validate_role("nonexistent", familiar_dir: tmp_dir)
    end
  end

  describe "validate_skill/2" do
    test "returns :ok and warns for unknown tools", %{tmp_dir: tmp_dir} do
      setup_fixture(tmp_dir, "skills", "future", """
      ---
      name: future
      description: Future skill
      tools:
        - read_file
        - quantum_compute
      ---
      Instructions.
      """)

      log =
        capture_log(fn ->
          assert :ok = Roles.validate_skill("future", familiar_dir: tmp_dir)
        end)

      assert log =~ "quantum_compute"
    end

    test "returns error when skill doesn't exist", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "skills"))

      assert {:error, {:skill_not_found, _}} =
               Roles.validate_skill("nonexistent", familiar_dir: tmp_dir)
    end
  end
end
