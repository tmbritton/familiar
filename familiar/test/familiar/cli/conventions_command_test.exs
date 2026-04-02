defmodule Familiar.CLI.ConventionsCommandTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.CLI.Main
  alias Familiar.Daemon.Paths

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    Paths.ensure_familiar_dir!()
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "parse_args/1 for conventions" do
    test "parses conventions command" do
      assert {"conventions", [], %{}} = Main.parse_args(["conventions"])
    end

    test "parses conventions with subcommand" do
      assert {"conventions", ["review"], %{}} = Main.parse_args(["conventions", "review"])
    end

    test "parses conventions with --json flag" do
      assert {"conventions", [], %{json: true}} = Main.parse_args(["conventions", "--json"])
    end
  end

  describe "run/2 with conventions list" do
    test "returns conventions from daemon" do
      deps =
        cli_deps(
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          conventions_fn: fn 4000 ->
            {:ok,
             [
               %{
                 text: "Source files use snake_case naming",
                 evidence_count: 61,
                 evidence_total: 64,
                 evidence_ratio: 0.95,
                 reviewed: false
               }
             ]}
          end
        )

      result = Main.run({"conventions", [], %{}}, deps)
      assert {:ok, %{conventions: conventions}} = result
      assert length(conventions) == 1
      assert hd(conventions).text =~ "snake_case"
    end

    test "returns empty list when no conventions" do
      deps =
        cli_deps(
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          conventions_fn: fn _port -> {:ok, []} end
        )

      result = Main.run({"conventions", [], %{}}, deps)
      assert {:ok, %{conventions: []}} = result
    end
  end

  describe "run/2 with conventions review" do
    test "runs interactive review and returns results" do
      deps =
        cli_deps(
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          conventions_fn: fn 4000 ->
            {:ok,
             [
               %{
                 id: 1,
                 text: "Uses snake_case",
                 evidence_count: 10,
                 evidence_total: 10,
                 reviewed: false
               }
             ]}
          end,
          review_fn: fn conventions, _opts ->
            {:ok, %{accepted: length(conventions), rejected: 0, edited: 0}}
          end
        )

      result = Main.run({"conventions", ["review"], %{}}, deps)

      assert {:ok, %{review_mode: true, accepted: 1, rejected: 0, edited: 0}} = result
    end
  end

  # -- Test Helpers --

  defp cli_deps(overrides \\ []) do
    %{
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
        Keyword.get(overrides, :version_compatible_fn, fn _cli, _daemon -> true end),
      prerequisites_fn:
        Keyword.get(overrides, :prerequisites_fn, fn _opts ->
          {:error,
           {:prerequisites_failed, %{missing: ["ollama"], instructions: "Install Ollama"}}}
        end),
      init_fn:
        Keyword.get(overrides, :init_fn, fn _opts ->
          {:ok, %{files_scanned: 0, entries_created: 0}}
        end),
      conventions_fn: Keyword.get(overrides, :conventions_fn, fn _port -> {:ok, []} end),
      review_fn:
        Keyword.get(overrides, :review_fn, fn convs, _opts ->
          {:ok, %{accepted: length(convs), rejected: 0, edited: 0}}
        end)
    }
  end
end
