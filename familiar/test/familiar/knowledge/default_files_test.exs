defmodule Familiar.Knowledge.DefaultFilesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @moduletag :tmp_dir

  alias Familiar.Knowledge.DefaultFiles
  alias Familiar.Roles
  alias Familiar.Roles.{Role, Skill}

  @expected_roles ~w(analyst coder reviewer librarian archivist project-manager)
  @expected_skills ~w(
    implement test research review-code
    search-knowledge summarize-results
    extract-knowledge capture-gotchas
    dispatch-tasks monitor-workers summarize-progress evaluate-failures
  )

  defp install_defaults(tmp_dir) do
    familiar_dir = Path.join(tmp_dir, ".familiar")
    File.mkdir_p!(familiar_dir)
    :ok = DefaultFiles.install(familiar_dir)
    familiar_dir
  end

  describe "install/1" do
    test "creates workflow files", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      workflows_dir = Path.join(familiar_dir, "workflows")
      assert File.dir?(workflows_dir)

      assert File.exists?(Path.join(workflows_dir, "feature-planning.md"))
      assert File.exists?(Path.join(workflows_dir, "feature-implementation.md"))
      assert File.exists?(Path.join(workflows_dir, "task-fix.md"))
    end

    test "creates all 6 role files", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      roles_dir = Path.join(familiar_dir, "roles")
      assert File.dir?(roles_dir)

      for role_name <- @expected_roles do
        assert File.exists?(Path.join(roles_dir, "#{role_name}.md")),
               "expected role file #{role_name}.md to exist"
      end
    end

    test "creates all 12 skill files", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      skills_dir = Path.join(familiar_dir, "skills")
      assert File.dir?(skills_dir)

      for skill_name <- @expected_skills do
        assert File.exists?(Path.join(skills_dir, "#{skill_name}.md")),
               "expected skill file #{skill_name}.md to exist"
      end
    end

    test "does not overwrite existing workflow files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      workflows_dir = Path.join(familiar_dir, "workflows")
      File.mkdir_p!(workflows_dir)

      custom_content = "# My custom workflow"
      File.write!(Path.join(workflows_dir, "feature-planning.md"), custom_content)

      :ok = DefaultFiles.install(familiar_dir)

      assert File.read!(Path.join(workflows_dir, "feature-planning.md")) == custom_content
    end

    test "does not overwrite existing role files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      roles_dir = Path.join(familiar_dir, "roles")
      File.mkdir_p!(roles_dir)

      custom_content = "# My custom analyst"
      File.write!(Path.join(roles_dir, "analyst.md"), custom_content)

      :ok = DefaultFiles.install(familiar_dir)

      assert File.read!(Path.join(roles_dir, "analyst.md")) == custom_content
    end

    test "does not overwrite existing skill files", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      skills_dir = Path.join(familiar_dir, "skills")
      File.mkdir_p!(skills_dir)

      custom_content = "# My custom implement skill"
      File.write!(Path.join(skills_dir, "implement.md"), custom_content)

      :ok = DefaultFiles.install(familiar_dir)

      assert File.read!(Path.join(skills_dir, "implement.md")) == custom_content
    end
  end

  describe "installed role files" do
    test "all role files load successfully via Roles API", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      for role_name <- @expected_roles do
        assert {:ok, %Role{} = role} = Roles.load_role(role_name, familiar_dir: familiar_dir),
               "failed to load role #{role_name}"

        assert role.name == role_name
        assert is_binary(role.description) and role.description != ""
        assert is_binary(role.system_prompt) and role.system_prompt != ""
        assert is_list(role.skills) and role.skills != []
      end
    end

    test "all role files pass cross-reference validation", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      for role_name <- @expected_roles do
        assert :ok = Roles.validate_role(role_name, familiar_dir: familiar_dir),
               "validation failed for role #{role_name}"
      end
    end

    test "project-manager has batch lifecycle", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      assert {:ok, %Role{lifecycle: :batch}} =
               Roles.load_role("project-manager", familiar_dir: familiar_dir)
    end

    test "non-PM roles default to ephemeral lifecycle", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      for role_name <- @expected_roles -- ["project-manager"] do
        assert {:ok, %Role{lifecycle: :ephemeral}} =
                 Roles.load_role(role_name, familiar_dir: familiar_dir),
               "expected ephemeral lifecycle for role #{role_name}"
      end
    end

    test "librarian prompt contains search refinement and summarization", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      assert {:ok, %Role{} = role} = Roles.load_role("librarian", familiar_dir: familiar_dir)

      assert role.system_prompt =~ "Search Refinement"
      assert role.system_prompt =~ "Summarization"
      assert role.system_prompt =~ "refined"
    end

    test "analyst prompt contains planning conversation instructions", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      assert {:ok, %Role{} = role} = Roles.load_role("analyst", familiar_dir: familiar_dir)

      assert role.system_prompt =~ "Planning Conversation"
      assert role.system_prompt =~ "specification"
      assert role.system_prompt =~ "acceptance criteria"
    end

    test "coder prompt contains safety rules", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      assert {:ok, %Role{} = role} = Roles.load_role("coder", familiar_dir: familiar_dir)

      assert role.system_prompt =~ "Safety"
      assert role.system_prompt =~ "project directory"
    end
  end

  describe "installed skill files" do
    test "all skill files load successfully via Roles API", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      for skill_name <- @expected_skills do
        assert {:ok, %Skill{} = skill} = Roles.load_skill(skill_name, familiar_dir: familiar_dir),
               "failed to load skill #{skill_name}"

        assert skill.name == skill_name
        assert is_binary(skill.description) and skill.description != ""
        assert is_binary(skill.instructions) and skill.instructions != ""
        assert is_list(skill.tools) and skill.tools != []
      end
    end

    test "all skill files pass tool validation (warnings for forward-declared tools)",
         %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      # Some skills reference future tools (spawn_agent, monitor_agents, broadcast_status)
      # These produce warnings but still pass validation
      log =
        capture_log(fn ->
          for skill_name <- @expected_skills do
            assert :ok = Roles.validate_skill(skill_name, familiar_dir: familiar_dir),
                   "validation failed for skill #{skill_name}"
          end
        end)

      # Forward-declared tools should each produce a warning
      assert log =~ "spawn_agent"
      assert log =~ "monitor_agents"
      assert log =~ "broadcast_status"
    end

    test "skills with only MVP tools produce no warnings", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      mvp_only_skills =
        ~w(implement test research review-code extract-knowledge capture-gotchas search-knowledge summarize-results)

      log =
        capture_log(fn ->
          for skill_name <- mvp_only_skills do
            :ok = Roles.validate_skill(skill_name, familiar_dir: familiar_dir)
          end
        end)

      assert log == ""
    end

    test "search-knowledge has constraints", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      assert {:ok, %Skill{} = skill} =
               Roles.load_skill("search-knowledge", familiar_dir: familiar_dir)

      assert skill.constraints == %{"max_iterations" => 5, "read_only" => true}
    end

    test "summarize-results has read_only constraint", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      assert {:ok, %Skill{} = skill} =
               Roles.load_skill("summarize-results", familiar_dir: familiar_dir)

      assert skill.constraints == %{"read_only" => true}
    end
  end
end
