defmodule Familiar.CLI.MainTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "parse_args/1" do
    test "parses health command" do
      assert {"health", [], %{}} = Main.parse_args(["health"])
    end

    test "parses version command" do
      assert {"version", [], %{}} = Main.parse_args(["version"])
    end

    test "parses daemon subcommand" do
      assert {"daemon", ["status"], %{}} = Main.parse_args(["daemon", "status"])
    end

    test "parses --json flag" do
      assert {"health", [], %{json: true}} = Main.parse_args(["health", "--json"])
    end

    test "parses --quiet flag" do
      assert {"health", [], %{quiet: true}} = Main.parse_args(["health", "--quiet"])
    end

    test "parses --help flag" do
      assert {"help", [], %{}} = Main.parse_args(["--help"])
    end

    test "returns help for empty args" do
      assert {"help", [], %{}} = Main.parse_args([])
    end

    test "preserves --json with --help" do
      assert {"help", [], %{json: true}} = Main.parse_args(["--help", "--json"])
    end

    test "parses combined flags" do
      assert {"health", [], %{json: true}} = Main.parse_args(["--json", "health"])
    end
  end

  describe "run/2 with version command" do
    test "returns version" do
      result = Main.run({"version", [], %{}}, deps())
      assert {:ok, %{version: _}} = result
    end
  end

  describe "run/2 with help command" do
    test "returns help text" do
      result = Main.run({"help", [], %{}}, deps())
      assert {:ok, %{help: help}} = result
      assert help =~ "fam"
    end
  end

  describe "run/2 with init mode detection" do
    test "returns init_required when no .familiar/ dir" do
      result = Main.run({"health", [], %{}}, deps())
      assert {:error, {:init_required, %{}}} = result
    end
  end

  describe "run/2 with health command" do
    test "returns health info when daemon is running" do
      Paths.ensure_familiar_dir!()

      health_deps =
        deps(
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          health_fn: fn 4000 -> {:ok, %{status: "ok", version: "0.1.0"}} end
        )

      result = Main.run({"health", [], %{}}, health_deps)
      assert {:ok, %{status: "ok", version: "0.1.0"}} = result
    end

    test "returns error when daemon unavailable" do
      Paths.ensure_familiar_dir!()

      err_deps =
        deps(ensure_running_fn: fn _opts -> {:error, {:daemon_unavailable, %{}}} end)

      result = Main.run({"health", [], %{}}, err_deps)
      assert {:error, {:daemon_unavailable, %{}}} = result
    end

    test "warns on version mismatch" do
      Paths.ensure_familiar_dir!()

      mismatch_deps =
        deps(
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          health_fn: fn 4000 -> {:ok, %{status: "ok", version: "9.0.0"}} end,
          version_compatible_fn: fn _cli, _daemon -> false end
        )

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          result = Main.run({"health", [], %{}}, mismatch_deps)
          assert {:ok, %{status: "ok", version: "9.0.0"}} = result
        end)

      assert output =~ "fam daemon restart"
    end
  end

  describe "run/2 with daemon subcommands" do
    test "daemon status returns status info" do
      Paths.ensure_familiar_dir!()

      status_deps =
        deps(daemon_status_fn: fn _opts -> {:running, %{port: 4000, version: "0.1.0"}} end)

      result = Main.run({"daemon", ["status"], %{}}, status_deps)
      assert {:ok, %{daemon: "running", port: 4000, version: "0.1.0"}} = result
    end

    test "daemon stop stops the daemon" do
      Paths.ensure_familiar_dir!()

      stop_deps =
        deps(stop_daemon_fn: fn _opts -> :ok end)

      result = Main.run({"daemon", ["stop"], %{}}, stop_deps)
      assert {:ok, %{status: "stopped"}} = result
    end

    test "daemon start starts the daemon" do
      Paths.ensure_familiar_dir!()

      start_deps =
        deps(ensure_running_fn: fn _opts -> {:ok, 4000} end)

      result = Main.run({"daemon", ["start"], %{}}, start_deps)
      assert {:ok, %{status: "started", port: 4000}} = result
    end
  end

  describe "run/2 with unknown command" do
    test "returns unknown_command error" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"bogus", [], %{}}, deps())
      assert {:error, {:unknown_command, %{command: "bogus"}}} = result
    end
  end

  describe "format_mode/1" do
    test "returns :json for json flag" do
      assert :json = Main.format_mode(%{json: true})
    end

    test "returns :quiet for quiet flag" do
      assert :quiet = Main.format_mode(%{quiet: true})
    end

    test "returns :text for no flags" do
      assert :text = Main.format_mode(%{})
    end
  end

  # -- Test helpers --

  defp deps(overrides \\ []) do
    %{
      ensure_running_fn:
        Keyword.get(overrides, :ensure_running_fn, fn _opts ->
          {:error, {:daemon_unavailable, %{}}}
        end),
      health_fn:
        Keyword.get(overrides, :health_fn, fn _port -> {:error, {:daemon_unavailable, %{}}} end),
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
