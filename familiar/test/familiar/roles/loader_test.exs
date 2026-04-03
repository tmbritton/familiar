defmodule Familiar.Roles.LoaderTest do
  use ExUnit.Case, async: true

  alias Familiar.Roles.Loader
  alias Familiar.Roles.{Role, Skill}

  @moduletag :tmp_dir

  defp write_file!(tmp_dir, name, content) do
    path = Path.join(tmp_dir, name)
    File.write!(path, content)
    path
  end

  describe "parse_file/1" do
    test "parses valid frontmatter and body", %{tmp_dir: tmp_dir} do
      path =
        write_file!(tmp_dir, "test.md", """
        ---
        name: coder
        description: A coding agent
        ---
        You are a coder.
        """)

      assert {:ok, %{frontmatter: fm, body: body}} = Loader.parse_file(path)
      assert fm["name"] == "coder"
      assert fm["description"] == "A coding agent"
      assert body == "You are a coder."
    end

    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nope.md")
      assert {:error, {:file_not_found, ^path}} = Loader.parse_file(path)
    end

    test "returns error for missing frontmatter delimiters", %{tmp_dir: tmp_dir} do
      path = write_file!(tmp_dir, "no_fm.md", "Just some text\nwithout frontmatter")

      assert {:error, {:malformed_frontmatter, "missing --- frontmatter delimiters"}} =
               Loader.parse_file(path)
    end

    test "returns error for malformed YAML", %{tmp_dir: tmp_dir} do
      path =
        write_file!(tmp_dir, "bad.md", """
        ---
        name: [unclosed
        ---
        body
        """)

      assert {:error, {:malformed_frontmatter, _}} = Loader.parse_file(path)
    end

    test "handles empty body", %{tmp_dir: tmp_dir} do
      path =
        write_file!(tmp_dir, "empty_body.md", """
        ---
        name: minimal
        ---
        """)

      assert {:ok, %{body: ""}} = Loader.parse_file(path)
    end

    test "returns error when frontmatter is a YAML list instead of a map", %{tmp_dir: tmp_dir} do
      path =
        write_file!(tmp_dir, "list_fm.md", """
        ---
        - item1
        - item2
        ---
        body
        """)

      assert {:error, {:malformed_frontmatter, "frontmatter must be a YAML mapping"}} =
               Loader.parse_file(path)
    end

    test "returns error with only one --- delimiter", %{tmp_dir: tmp_dir} do
      path = write_file!(tmp_dir, "one_delim.md", "---\nname: test\nbody text")

      assert {:error, {:malformed_frontmatter, "missing --- frontmatter delimiters"}} =
               Loader.parse_file(path)
    end
  end

  describe "build_role/1" do
    test "builds role with all fields" do
      parsed = %{
        frontmatter: %{
          "name" => "coder",
          "description" => "Writes code",
          "model" => "sonnet",
          "lifecycle" => "session",
          "skills" => ["implement", "test"]
        },
        body: "You are a coder."
      }

      assert {:ok, %Role{} = role} = Loader.build_role(parsed)
      assert role.name == "coder"
      assert role.description == "Writes code"
      assert role.model == "sonnet"
      assert role.lifecycle == :session
      assert role.skills == ["implement", "test"]
      assert role.system_prompt == "You are a coder."
    end

    test "applies defaults for model and lifecycle" do
      parsed = %{
        frontmatter: %{
          "name" => "reviewer",
          "description" => "Reviews code",
          "skills" => ["review"]
        },
        body: "Review carefully."
      }

      assert {:ok, %Role{} = role} = Loader.build_role(parsed)
      assert role.model == "default"
      assert role.lifecycle == :ephemeral
    end

    test "wraps single skill string into list" do
      parsed = %{
        frontmatter: %{
          "name" => "simple",
          "description" => "One skill",
          "skills" => "implement"
        },
        body: "Go."
      }

      assert {:ok, %Role{skills: ["implement"]}} = Loader.build_role(parsed)
    end

    test "returns error for missing required fields" do
      parsed = %{frontmatter: %{"name" => "bad"}, body: "text"}

      assert {:error, {:invalid_role, %{name: "bad", reason: reason}}} = Loader.build_role(parsed)
      assert reason =~ "description"
      assert reason =~ "skills"
    end

    test "returns error for invalid lifecycle" do
      parsed = %{
        frontmatter: %{
          "name" => "bad_lc",
          "description" => "test",
          "skills" => ["x"],
          "lifecycle" => "forever"
        },
        body: "text"
      }

      assert {:error, {:invalid_role, %{name: "bad_lc", reason: reason}}} =
               Loader.build_role(parsed)

      assert reason =~ "invalid lifecycle"
    end

    test "returns error when name is missing" do
      parsed = %{frontmatter: %{"description" => "test", "skills" => ["x"]}, body: "text"}

      assert {:error, {:invalid_role, %{name: "unknown", reason: reason}}} =
               Loader.build_role(parsed)

      assert reason =~ "name"
    end

    test "returns error when name is not a string" do
      parsed = %{
        frontmatter: %{"name" => 123, "description" => "test", "skills" => ["x"]},
        body: "text"
      }

      assert {:error, {:invalid_role, %{reason: reason}}} = Loader.build_role(parsed)
      assert reason =~ "must be strings"
    end

    test "returns error when skills contains non-strings" do
      parsed = %{
        frontmatter: %{"name" => "bad", "description" => "test", "skills" => [1, 2]},
        body: "text"
      }

      assert {:error, {:invalid_role, %{reason: reason}}} = Loader.build_role(parsed)
      assert reason =~ "skills"
    end
  end

  describe "build_skill/1" do
    test "builds skill with all fields" do
      parsed = %{
        frontmatter: %{
          "name" => "implement",
          "description" => "Write code",
          "tools" => ["read_file", "write_file"],
          "constraints" => %{"max_files" => 10}
        },
        body: "Implementation instructions."
      }

      assert {:ok, %Skill{} = skill} = Loader.build_skill(parsed)
      assert skill.name == "implement"
      assert skill.tools == ["read_file", "write_file"]
      assert skill.constraints == %{"max_files" => 10}
      assert skill.instructions == "Implementation instructions."
    end

    test "defaults constraints to empty map" do
      parsed = %{
        frontmatter: %{
          "name" => "review",
          "description" => "Review code",
          "tools" => ["read_file"]
        },
        body: "Review."
      }

      assert {:ok, %Skill{constraints: %{}}} = Loader.build_skill(parsed)
    end

    test "wraps single tool string into list" do
      parsed = %{
        frontmatter: %{
          "name" => "simple",
          "description" => "One tool",
          "tools" => "read_file"
        },
        body: "Go."
      }

      assert {:ok, %Skill{tools: ["read_file"]}} = Loader.build_skill(parsed)
    end

    test "returns error for missing required fields" do
      parsed = %{frontmatter: %{"name" => "bad"}, body: "text"}

      assert {:error, {:invalid_skill, %{name: "bad", reason: reason}}} =
               Loader.build_skill(parsed)

      assert reason =~ "description"
      assert reason =~ "tools"
    end

    test "returns error when constraints is not a map" do
      parsed = %{
        frontmatter: %{
          "name" => "bad",
          "description" => "test",
          "tools" => ["read_file"],
          "constraints" => "not a map"
        },
        body: "text"
      }

      assert {:error, {:invalid_skill, %{reason: reason}}} = Loader.build_skill(parsed)
      assert reason =~ "constraints"
    end

    test "returns error when tools contains non-strings" do
      parsed = %{
        frontmatter: %{"name" => "bad", "description" => "test", "tools" => [1, true]},
        body: "text"
      }

      assert {:error, {:invalid_skill, %{reason: reason}}} = Loader.build_skill(parsed)
      assert reason =~ "tools"
    end
  end
end
