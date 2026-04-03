defmodule Familiar.Roles.ValidatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Familiar.Roles.{Role, Skill, Validator}

  @moduletag :tmp_dir

  defp setup_skills(tmp_dir, skill_names) do
    skills_dir = Path.join(tmp_dir, "skills")
    File.mkdir_p!(skills_dir)

    for name <- skill_names do
      File.write!(Path.join(skills_dir, "#{name}.md"), """
      ---
      name: #{name}
      description: A skill
      tools:
        - read_file
      ---
      Instructions.
      """)
    end

    tmp_dir
  end

  describe "validate_role/2" do
    test "returns :ok when all skills exist", %{tmp_dir: tmp_dir} do
      setup_skills(tmp_dir, ["implement", "test"])

      role = %Role{
        name: "coder",
        description: "Writes code",
        skills: ["implement", "test"],
        system_prompt: "Go."
      }

      assert :ok = Validator.validate_role(role, familiar_dir: tmp_dir)
    end

    test "returns error when a skill is missing", %{tmp_dir: tmp_dir} do
      setup_skills(tmp_dir, ["implement"])

      role = %Role{
        name: "coder",
        description: "Writes code",
        skills: ["implement", "missing_skill"],
        system_prompt: "Go."
      }

      assert {:error, {:invalid_role, %{name: "coder", reason: reason}}} =
               Validator.validate_role(role, familiar_dir: tmp_dir)

      assert reason =~ "missing_skill"
      assert reason =~ "does not exist"
    end

    test "returns error for multiple missing skills", %{tmp_dir: tmp_dir} do
      setup_skills(tmp_dir, [])

      role = %Role{
        name: "bad",
        description: "test",
        skills: ["alpha", "beta"],
        system_prompt: "Go."
      }

      assert {:error, {:invalid_role, %{reason: reason}}} =
               Validator.validate_role(role, familiar_dir: tmp_dir)

      assert reason =~ "alpha"
      assert reason =~ "beta"
    end
  end

  describe "validate_skill/2" do
    test "returns :ok for known tools" do
      skill = %Skill{
        name: "implement",
        description: "Write code",
        tools: ["read_file", "write_file"],
        instructions: "Go."
      }

      assert :ok = Validator.validate_skill(skill)
    end

    test "logs warning for unknown tools but still returns :ok" do
      skill = %Skill{
        name: "future",
        description: "test",
        tools: ["read_file", "quantum_compute"],
        instructions: "Go."
      }

      log =
        capture_log(fn ->
          assert :ok = Validator.validate_skill(skill)
        end)

      assert log =~ "quantum_compute"
      assert log =~ "unknown tool"
    end

    test "accepts custom known_tools list" do
      skill = %Skill{
        name: "custom",
        description: "test",
        tools: ["custom_tool"],
        instructions: "Go."
      }

      # No warning when tool is in the custom list
      log =
        capture_log(fn ->
          assert :ok = Validator.validate_skill(skill, known_tools: ["custom_tool"])
        end)

      assert log == ""
    end
  end

  describe "mvp_tools/0" do
    test "returns a list of strings" do
      tools = Validator.mvp_tools()
      assert is_list(tools)
      assert "read_file" in tools
      assert "search_context" in tools
    end
  end
end
