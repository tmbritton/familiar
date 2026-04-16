defmodule Familiar.Config.GeneratorTest do
  use ExUnit.Case, async: true

  alias Familiar.Config.Generator

  @moduletag :tmp_dir

  describe "generate_default/2" do
    test "creates config.toml with provider defaults", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir)

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
      # No language section
      refute content =~ "[language]"
    end

    test "does not overwrite existing config.toml", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      config_path = Path.join(familiar_dir, "config.toml")
      File.write!(config_path, "# custom config\n")

      :ok = Generator.generate_default(familiar_dir)

      assert File.read!(config_path) == "# custom config\n"
    end

    test "generated config is valid TOML", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir)

      config_path = Path.join(familiar_dir, "config.toml")
      assert {:ok, _parsed} = Toml.decode_file(config_path)
    end

    test "includes scan and notifications sections", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")
      File.mkdir_p!(familiar_dir)

      :ok = Generator.generate_default(familiar_dir)

      content = File.read!(Path.join(familiar_dir, "config.toml"))
      assert content =~ "[scan]"
      assert content =~ "max_files"
      assert content =~ "[notifications]"
      assert content =~ "provider"
    end
  end
end
