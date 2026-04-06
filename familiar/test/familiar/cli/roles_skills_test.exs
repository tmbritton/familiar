defmodule Familiar.CLI.RolesSkillsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  defp deps(overrides \\ []) do
    base = %{
      ensure_running_fn: fn _opts -> {:ok, 4000} end,
      health_fn: fn _port -> {:ok, %{status: "ok", version: "0.1.0"}} end,
      daemon_status_fn: fn _opts -> {:stopped, %{}} end,
      stop_daemon_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end
    }

    Map.merge(base, Map.new(overrides))
  end

  # == Roles ==

  describe "fam roles" do
    test "lists all roles" do
      roles = [
        %{name: "analyst", description: "Analysis", skills: ~w(research), system_prompt: "..."},
        %{name: "coder", description: "Coding", skills: ~w(implement test), system_prompt: "..."}
      ]

      role_structs =
        Enum.map(roles, fn r ->
          struct!(Familiar.Roles.Role, Map.put(r, :skills, r.skills))
        end)

      d = deps(list_roles_fn: fn _opts -> {:ok, role_structs} end)

      assert {:ok, %{roles: result}} = Main.run({"roles", [], %{}}, d)
      assert length(result) == 2
      assert Enum.find(result, &(&1.name == "analyst"))
      assert Enum.find(result, &(&1.name == "coder")).skills_count == 2
    end

    test "returns error when roles dir missing" do
      d = deps(list_roles_fn: fn _opts -> {:error, {:no_roles_dir, %{}}} end)

      assert {:error, {:no_roles_dir, _}} = Main.run({"roles", [], %{}}, d)
    end
  end

  describe "fam roles <name>" do
    test "shows role details" do
      role = %Familiar.Roles.Role{
        name: "analyst",
        description: "Planning analyst",
        model: "default",
        lifecycle: :ephemeral,
        skills: ~w(research implement),
        system_prompt: "You are a planning analyst who researches features."
      }

      d = deps(load_role_fn: fn "analyst", _opts -> {:ok, role} end)

      assert {:ok, %{role: detail}} = Main.run({"roles", ["analyst"], %{}}, d)
      assert detail.name == "analyst"
      assert detail.description == "Planning analyst"
      assert detail.model == "default"
      assert detail.lifecycle == :ephemeral
      assert detail.skills == ~w(research implement)
      assert detail.prompt_preview =~ "planning analyst"
    end

    test "returns error for unknown role" do
      d = deps(load_role_fn: fn "nope", _opts -> {:error, {:role_not_found, %{name: "nope"}}} end)

      assert {:error, {:role_not_found, %{name: "nope"}}} =
               Main.run({"roles", ["nope"], %{}}, d)
    end
  end

  # == Skills ==

  describe "fam skills" do
    test "lists all skills" do
      skills = [
        %{
          name: "implement",
          description: "Write code",
          tools: ~w(read_file write_file),
          instructions: "..."
        },
        %{
          name: "research",
          description: "Search context",
          tools: ~w(search_files),
          instructions: "..."
        }
      ]

      skill_structs = Enum.map(skills, &struct!(Familiar.Roles.Skill, &1))
      d = deps(list_skills_fn: fn _opts -> {:ok, skill_structs} end)

      assert {:ok, %{skills: result}} = Main.run({"skills", [], %{}}, d)
      assert length(result) == 2
      assert Enum.find(result, &(&1.name == "implement")).tools_count == 2
    end
  end

  describe "fam skills <name>" do
    test "shows skill details" do
      skill = %Familiar.Roles.Skill{
        name: "implement",
        description: "Write and modify code files",
        tools: ~w(read_file write_file run_command),
        constraints: %{},
        instructions: "Follow project conventions and write clean code."
      }

      d = deps(load_skill_fn: fn "implement", _opts -> {:ok, skill} end)

      assert {:ok, %{skill: detail}} = Main.run({"skills", ["implement"], %{}}, d)
      assert detail.name == "implement"
      assert detail.tools == ~w(read_file write_file run_command)
      assert detail.instructions_preview =~ "conventions"
    end

    test "returns error for unknown skill" do
      d =
        deps(
          load_skill_fn: fn "nope", _opts ->
            {:error, {:skill_not_found, %{name: "nope"}}}
          end
        )

      assert {:error, {:skill_not_found, %{name: "nope"}}} =
               Main.run({"skills", ["nope"], %{}}, d)
    end
  end

  # == Output formatting ==

  describe "output formatting" do
    test "json mode returns roles list" do
      result = {:ok, %{roles: [%{name: "analyst", description: "A", skills_count: 2}]}}
      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert [role] = decoded["data"]["roles"]
      assert role["name"] == "analyst"
    end

    test "json mode returns skill detail" do
      result =
        {:ok,
         %{
           skill: %{
             name: "implement",
             description: "Code",
             tools: ["read_file"],
             constraints: %{},
             instructions_preview: "Write code."
           }
         }}

      json = Output.format(result, :json)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["data"]["skill"]["name"] == "implement"
    end

    test "quiet mode for roles list" do
      result = {:ok, %{roles: [%{}, %{}, %{}]}}
      assert Output.format(result, :quiet) == "roles:3"
    end

    test "quiet mode for role detail" do
      result = {:ok, %{role: %{name: "analyst"}}}
      assert Output.format(result, :quiet) == "role:analyst"
    end

    test "quiet mode for skills list" do
      result = {:ok, %{skills: [%{}, %{}]}}
      assert Output.format(result, :quiet) == "skills:2"
    end

    test "quiet mode for skill detail" do
      result = {:ok, %{skill: %{name: "implement"}}}
      assert Output.format(result, :quiet) == "skill:implement"
    end
  end
end
