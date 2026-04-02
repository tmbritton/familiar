defmodule Familiar.CLI.InitCommandTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "parse_args/1 for init" do
    test "parses init command" do
      assert {"init", [], %{}} = Main.parse_args(["init"])
    end

    test "parses init with --json flag" do
      assert {"init", [], %{json: true}} = Main.parse_args(["init", "--json"])
    end
  end

  describe "run/2 with init command" do
    test "runs init when no .familiar/ exists" do
      deps = init_deps(init_fn: fn _opts -> {:ok, %{files_scanned: 5, entries_created: 10}} end)

      result = Main.run({"init", [], %{}}, deps)
      assert {:ok, %{files_scanned: 5, entries_created: 10}} = result
    end

    test "returns already_initialized when .familiar/ exists" do
      Paths.ensure_familiar_dir!()
      deps = init_deps()

      result = Main.run({"init", [], %{}}, deps)
      assert {:error, {:already_initialized, _}} = result
    end

    test "returns prerequisite error" do
      deps =
        init_deps(
          prerequisites_fn: fn _opts ->
            {:error,
             {:prerequisites_failed, %{missing: ["ollama"], instructions: "Install Ollama"}}}
          end
        )

      result = Main.run({"init", [], %{}}, deps)
      assert {:error, {:prerequisites_failed, _}} = result
    end
  end

  describe "auto-init from other commands" do
    test "triggers init when init_required and auto_init enabled" do
      deps =
        init_deps(
          init_fn: fn _opts -> {:ok, %{files_scanned: 3, entries_created: 6}} end,
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          health_fn: fn 4000 -> {:ok, %{status: "ok", version: "0.1.0"}} end
        )

      # Health command with no .familiar/ should trigger auto-init
      result = Main.run({"health", [], %{}}, deps)
      # After auto-init succeeds, the original command runs
      assert {:ok, %{status: "ok"}} = result
    end
  end

  # -- Test Helpers --

  defp init_deps(overrides \\ []) do
    %{
      prerequisites_fn:
        Keyword.get(overrides, :prerequisites_fn, fn _opts ->
          {:ok, %{base_url: "http://localhost:11434"}}
        end),
      init_fn:
        Keyword.get(overrides, :init_fn, fn _opts ->
          {:ok, %{files_scanned: 0, entries_created: 0}}
        end),
      ensure_running_fn:
        Keyword.get(overrides, :ensure_running_fn, fn _opts ->
          {:error, {:daemon_unavailable, %{}}}
        end),
      health_fn:
        Keyword.get(overrides, :health_fn, fn _port ->
          {:error, {:daemon_unavailable, %{}}}
        end),
      daemon_status_fn:
        Keyword.get(overrides, :daemon_status_fn, fn _opts -> {:stopped, %{}} end),
      stop_daemon_fn:
        Keyword.get(overrides, :stop_daemon_fn, fn _opts ->
          {:error, {:daemon_unavailable, %{}}}
        end),
      version_compatible_fn:
        Keyword.get(overrides, :version_compatible_fn, fn _cli, _daemon -> true end)
    }
  end
end
