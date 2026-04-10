defmodule Familiar.Knowledge.DefaultFilesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @moduletag :tmp_dir

  alias Familiar.Execution.WorkflowRunner
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

    test "all skill files pass tool validation with no warnings", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      log =
        capture_log(fn ->
          for skill_name <- @expected_skills do
            assert :ok = Roles.validate_skill(skill_name, familiar_dir: familiar_dir),
                   "validation failed for skill #{skill_name}"
          end
        end)

      # All referenced tools are now in the MVP tools list — no unknown-tool warnings.
      # NOTE: assert on *content*, not on `log == ""`. `capture_log` collects
      # messages from every process in the BEAM, so unrelated background
      # processes can leak output into the captured string.
      refute log =~ "unknown tool"
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

    test "all skill tool references are valid registered tool names", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)

      # Builtin tools + extension tools
      valid_tools =
        MapSet.new(~w(
          read_file write_file delete_file list_files search_files
          run_command spawn_agent run_workflow monitor_agents
          broadcast_status signal_ready search_context store_context
        ))

      for skill_name <- @expected_skills do
        {:ok, skill} = Roles.load_skill(skill_name, familiar_dir: familiar_dir)

        for tool <- skill.tools do
          assert MapSet.member?(valid_tools, tool),
                 "Skill '#{skill_name}' references unknown tool '#{tool}'. " <>
                   "Valid tools: #{Enum.join(valid_tools, ", ")}"
        end
      end
    end
  end

  describe "installed workflow files" do
    test "workflow files have valid YAML frontmatter for WorkflowRunner", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      workflows_dir = Path.join(familiar_dir, "workflows")

      for filename <- ~w(feature-planning.md feature-implementation.md task-fix.md) do
        content = File.read!(Path.join(workflows_dir, filename))

        # Extract YAML frontmatter
        assert content =~ ~r/\A\s*---\n/,
               "#{filename} missing YAML frontmatter"

        [_, yaml_str | _] = String.split(content, "---", parts: 3)
        {:ok, yaml} = YamlElixir.read_from_string(yaml_str)

        assert is_binary(yaml["name"]), "#{filename} missing 'name' in frontmatter"
        assert is_binary(yaml["description"]), "#{filename} missing 'description' in frontmatter"

        assert is_list(yaml["steps"]) and yaml["steps"] != [],
               "#{filename} missing 'steps' in frontmatter"

        for step <- yaml["steps"] do
          assert is_binary(step["name"]), "#{filename} step missing 'name'"
          assert is_binary(step["role"]), "#{filename} step missing 'role'"
        end
      end
    end

    test "workflow step roles reference valid default roles", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      workflows_dir = Path.join(familiar_dir, "workflows")

      for filename <- ~w(feature-planning.md feature-implementation.md task-fix.md) do
        content = File.read!(Path.join(workflows_dir, filename))
        [_, yaml_str | _] = String.split(content, "---", parts: 3)
        {:ok, yaml} = YamlElixir.read_from_string(yaml_str)

        for step <- yaml["steps"] do
          assert step["role"] in @expected_roles,
                 "#{filename} step '#{step["name"]}' references unknown role '#{step["role"]}'"
        end
      end
    end

    test "WorkflowRunner.parse/1 succeeds on all default workflows", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      workflows_dir = Path.join(familiar_dir, "workflows")

      expected = %{
        "feature-planning.md" => {3, ~w(research draft-spec review-spec)},
        "feature-implementation.md" => {3, ~w(implement test review)},
        "task-fix.md" => {3, ~w(diagnose fix verify)}
      }

      for {filename, {step_count, step_names}} <- expected do
        path = Path.join(workflows_dir, filename)
        assert {:ok, workflow} = WorkflowRunner.parse(path), "Failed to parse #{filename}"

        assert length(workflow.steps) == step_count,
               "#{filename}: expected #{step_count} steps, got #{length(workflow.steps)}"

        actual_names = Enum.map(workflow.steps, & &1.name)
        assert actual_names == step_names, "#{filename}: step names mismatch"
      end
    end

    test "feature-planning draft-spec step has interactive mode", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      path = Path.join([familiar_dir, "workflows", "feature-planning.md"])
      assert {:ok, workflow} = WorkflowRunner.parse(path)

      [research, draft_spec, review_spec] = workflow.steps
      assert research.mode == :autonomous
      assert draft_spec.mode == :interactive
      assert review_spec.mode == :autonomous
    end

    test "workflow steps have valid input references to prior steps", %{tmp_dir: tmp_dir} do
      familiar_dir = install_defaults(tmp_dir)
      workflows_dir = Path.join(familiar_dir, "workflows")

      for filename <- ~w(feature-planning.md feature-implementation.md task-fix.md) do
        path = Path.join(workflows_dir, filename)
        {:ok, workflow} = WorkflowRunner.parse(path)

        # First step should have no inputs
        first = hd(workflow.steps)
        assert first.input == [], "#{filename}: first step '#{first.name}' should have no inputs"

        # Later steps should reference only prior steps
        prior_names = MapSet.new()

        Enum.reduce(workflow.steps, prior_names, fn step, prior ->
          for ref <- step.input do
            assert MapSet.member?(prior, ref),
                   "#{filename}: step '#{step.name}' references '#{ref}' which is not a prior step"
          end

          MapSet.put(prior, step.name)
        end)

        # At least one step should have inputs (workflows are connected)
        has_inputs = Enum.any?(workflow.steps, &(&1.input != []))

        assert has_inputs,
               "#{filename}: no steps have input references — workflow is disconnected"
      end
    end
  end
end
