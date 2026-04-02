defmodule Familiar.Knowledge.CommandValidator do
  @moduledoc """
  Detects and validates language-specific build, test, and lint commands.

  Auto-detects the project language from indicator files, determines
  the standard commands, and validates each command is available via
  the Shell behaviour port.
  """

  @language_indicators Familiar.Knowledge.LanguageIndicators.short_list()

  # Safe probe commands only — never run actual builds/tests during init
  @language_commands %{
    "elixir" => %{
      test: {"mix", ["help", "test"]},
      build: {"mix", ["help", "compile"]},
      lint: {"mix", ["help", "credo"]}
    },
    "nodejs" => %{
      test: {"npm", ["help", "test"]},
      build: {"npm", ["help", "run"]},
      lint: {"npx", ["--help"]}
    },
    "go" => %{
      test: {"go", ["help", "test"]},
      build: {"go", ["help", "build"]},
      lint: {"golangci-lint", ["--help"]}
    },
    "rust" => %{
      test: {"cargo", ["help", "test"]},
      build: {"cargo", ["help", "build"]},
      lint: {"cargo", ["help", "clippy"]}
    },
    "python" => %{
      test: {"pytest", ["--help"]},
      lint: {"ruff", ["--help"]}
    },
    "ruby" => %{
      test: {"bundle", ["exec", "rspec", "--help"]},
      lint: {"bundle", ["exec", "rubocop", "--help"]}
    }
  }

  @doc """
  Detect the primary language from project file list.

  Returns `{:ok, language_string}`.
  """
  @spec detect_language([map()]) :: {:ok, String.t()}
  def detect_language(files) do
    basenames = Enum.map(files, &Path.basename(&1.relative_path))

    language =
      Enum.find_value(@language_indicators, "unknown", fn {indicator, lang} ->
        if indicator in basenames, do: lang
      end)

    {:ok, language}
  end

  @doc """
  Get the standard commands for a language.
  """
  @spec commands_for_language(String.t()) :: map()
  def commands_for_language(language) do
    Map.get(@language_commands, language, %{})
  end

  @doc """
  Validate language-specific commands for a project.

  Options:
  - `:shell` — Shell implementation (default: from app config)
  """
  @spec validate([map()], keyword()) :: {:ok, map()}
  def validate(files, opts \\ []) do
    shell = shell_impl(opts)
    {:ok, language} = detect_language(files)
    commands = commands_for_language(language)

    if commands == %{} do
      {:ok, %{language: language, commands: [], failures: []}}
    else
      results = validate_commands(commands, shell)

      validated =
        results
        |> Enum.filter(&match?({_, :ok}, &1))
        |> Enum.map(fn {name, :ok} -> name end)

      failures =
        results
        |> Enum.filter(&match?({_, {:error, _}}, &1))
        |> Enum.map(fn {name, {:error, reason}} -> %{command: name, reason: reason} end)

      {:ok, %{language: language, commands: validated, failures: failures}}
    end
  end

  # -- Private --

  defp validate_commands(commands, shell) do
    Enum.map(commands, fn {name, {cmd, args}} ->
      case shell.cmd(cmd, args, []) do
        {:ok, %{exit_code: 0}} ->
          {name, :ok}

        {:ok, %{exit_code: code, output: output}} ->
          {name, {:error, {:command_failed, %{exit_code: code, output: output}}}}

        {:error, reason} ->
          {name, {:error, reason}}
      end
    end)
  end

  defp shell_impl(opts) do
    Keyword.get_lazy(opts, :shell, fn ->
      Application.get_env(:familiar, Familiar.System.Shell, Familiar.System.RealShell)
    end)
  end
end
