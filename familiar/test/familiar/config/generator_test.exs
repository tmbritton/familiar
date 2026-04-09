defmodule Familiar.Config.GeneratorTest do
  use ExUnit.Case, async: true

  alias Familiar.Config.Generator

  @moduletag :tmp_dir

  describe "generate_default/2" do
    test "creates config.toml with provider defaults", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, nil)

      config_path = Path.join(familiar_dir, "config.toml")
      assert File.exists?(config_path)

      content = File.read!(config_path)
      assert content =~ "[providers.openrouter]"
      assert content =~ ~s(type = "openai_compatible")
      assert content =~ ~s(base_url = "https://openrouter.ai/api/v1")
      assert content =~ ~s(api_key = "${OPENROUTER_API_KEY}")
      assert content =~ "default = true"
      assert content =~ "${ENV_VAR}"
      # Other providers commented out
      assert content =~ "# [providers.deepseek]"
      assert content =~ "# [providers.ollama]"
    end

    test "populates language section when elixir detected", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, "elixir")

      content = File.read!(Path.join(familiar_dir, "config.toml"))
      assert content =~ "[language]"
      assert content =~ ~s(name = "elixir")
      assert content =~ ~s(test_command = "mix test")
      assert content =~ ~s(build_command = "mix compile")
      assert content =~ ~s(dep_file = "mix.exs")
    end

    test "populates language section when go detected", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, "go")

      content = File.read!(Path.join(familiar_dir, "config.toml"))
      assert content =~ ~s(name = "go")
      assert content =~ ~s(test_command = "go test ./...")
      assert content =~ ~s(dep_file = "go.mod")
    end

    test "comments out language section when no language detected", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, nil)

      content = File.read!(Path.join(familiar_dir, "config.toml"))
      assert content =~ "[language]"
      assert content =~ "# name ="
    end

    test "does not overwrite existing config.toml", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      config_path = Path.join(familiar_dir, "config.toml")
      File.write!(config_path, "# custom config\n")

      :ok = Generator.generate_default(familiar_dir, "elixir")

      assert File.read!(config_path) == "# custom config\n"
    end

    test "generated config is valid TOML", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, "elixir")

      config_path = Path.join(familiar_dir, "config.toml")
      assert {:ok, _parsed} = Toml.decode_file(config_path)
    end

    test "includes scan and notifications sections", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir, nil)

      content = File.read!(Path.join(familiar_dir, "config.toml"))
      assert content =~ "[scan]"
      assert content =~ "max_files"
      assert content =~ "[notifications]"
      assert content =~ "provider"
    end
  end
end
