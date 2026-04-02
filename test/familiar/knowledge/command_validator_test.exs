defmodule Familiar.Knowledge.CommandValidatorTest do
  use ExUnit.Case, async: false
  use Familiar.MockCase

  alias Familiar.Knowledge.CommandValidator

  describe "detect_language/1" do
    test "detects Elixir from mix.exs" do
      files = [%{relative_path: "mix.exs"}, %{relative_path: "lib/app.ex"}]
      assert {:ok, "elixir"} = CommandValidator.detect_language(files)
    end

    test "detects Node.js from package.json" do
      files = [%{relative_path: "package.json"}, %{relative_path: "src/index.js"}]
      assert {:ok, "nodejs"} = CommandValidator.detect_language(files)
    end

    test "detects Go from go.mod" do
      files = [%{relative_path: "go.mod"}, %{relative_path: "main.go"}]
      assert {:ok, "go"} = CommandValidator.detect_language(files)
    end

    test "detects Rust from Cargo.toml" do
      files = [%{relative_path: "Cargo.toml"}, %{relative_path: "src/main.rs"}]
      assert {:ok, "rust"} = CommandValidator.detect_language(files)
    end

    test "detects Python from pyproject.toml" do
      files = [%{relative_path: "pyproject.toml"}, %{relative_path: "src/main.py"}]
      assert {:ok, "python"} = CommandValidator.detect_language(files)
    end

    test "detects Ruby from Gemfile" do
      files = [%{relative_path: "Gemfile"}, %{relative_path: "lib/app.rb"}]
      assert {:ok, "ruby"} = CommandValidator.detect_language(files)
    end

    test "returns unknown for unrecognized projects" do
      files = [%{relative_path: "README.md"}]
      assert {:ok, "unknown"} = CommandValidator.detect_language(files)
    end
  end

  describe "commands_for_language/1" do
    test "returns Elixir commands" do
      cmds = CommandValidator.commands_for_language("elixir")
      assert cmds[:test] == {"mix", ["help", "test"]}
      assert cmds[:build] == {"mix", ["help", "compile"]}
      assert cmds[:lint] == {"mix", ["help", "credo"]}
    end

    test "returns empty map for unknown language" do
      assert %{} == CommandValidator.commands_for_language("unknown")
    end
  end

  describe "validate/2" do
    test "validates commands via shell" do
      Mox.expect(Familiar.System.ShellMock, :cmd, 3, fn cmd, _args, _opts ->
        case cmd do
          "mix" -> {:ok, %{output: "Usage: mix ...", exit_code: 0}}
          _ -> {:ok, %{output: "", exit_code: 0}}
        end
      end)

      files = [%{relative_path: "mix.exs"}]
      result = CommandValidator.validate(files, shell: Familiar.System.ShellMock)

      assert {:ok, validated} = result
      assert validated.language == "elixir"
      assert is_list(validated.commands)
    end

    test "reports validation failures for non-zero exit codes" do
      Mox.expect(Familiar.System.ShellMock, :cmd, 3, fn _cmd, _args, _opts ->
        {:ok, %{output: "command failed", exit_code: 1}}
      end)

      files = [%{relative_path: "mix.exs"}]
      result = CommandValidator.validate(files, shell: Familiar.System.ShellMock)

      assert {:ok, validated} = result
      assert length(validated.failures) == 3
    end

    test "reports validation failures for shell errors" do
      Mox.expect(Familiar.System.ShellMock, :cmd, 3, fn _cmd, _args, _opts ->
        {:error, {:shell_error, %{reason: "command not found"}}}
      end)

      files = [%{relative_path: "mix.exs"}]
      result = CommandValidator.validate(files, shell: Familiar.System.ShellMock)

      assert {:ok, validated} = result
      assert length(validated.failures) == 3
    end

    test "skips validation for unknown languages" do
      files = [%{relative_path: "README.md"}]
      result = CommandValidator.validate(files, shell: Familiar.System.ShellMock)

      assert {:ok, validated} = result
      assert validated.language == "unknown"
      assert validated.commands == []
    end
  end
end
