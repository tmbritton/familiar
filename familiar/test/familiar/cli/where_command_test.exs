defmodule Familiar.CLI.WhereCommandTest do
  @moduledoc """
  Tests for `fam where` — the project-directory resolution debug command.

  `async: true` because every test injects `env_getter`, `cwd_getter`, and
  `daemon_status_fn` via the `deps` map. `Main.run({"where", _, _}, deps)`
  is the only entry point and it calls `Paths.resolve_project_dir/2`
  directly with fully-injected opts — no `Application.get_env/put_env`,
  no real filesystem reads outside the injected cwd.
  """

  use ExUnit.Case, async: true

  alias Familiar.CLI.Main
  alias Familiar.CLI.Output
  alias Familiar.Daemon.Paths

  setup do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "where_command_test",
        "#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(tmp_dir)

    # Same ancestor-safety check as paths_resolve_test.exs — fail the
    # setup loudly if `/tmp` (or wherever System.tmp_dir! points) has a
    # stray `.familiar/` ancestor that would poison walk-up tests.
    case Paths.find_familiar_root(tmp_dir) do
      :not_found ->
        :ok

      {:ok, poisoned} ->
        flunk("""
        Test fixture root #{tmp_dir} has a `.familiar/` ancestor at #{poisoned}.
        Walk-up-based tests cannot run from here.
        """)
    end

    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  defp base_deps(overrides \\ %{}) do
    Map.merge(
      %{
        env_getter: fn -> nil end,
        # Default to "/" so tests that don't set cwd_getter get a
        # predictable (and guaranteed-not-a-Familiar-project) starting
        # point that terminates walk-up at the root immediately.
        cwd_getter: fn -> "/" end,
        daemon_status_fn: fn _opts -> {:stopped, %{}} end
      },
      overrides
    )
  end

  describe "parse_args recognizes --project-dir flag" do
    test "accepts --project-dir with a value" do
      assert {"where", [], %{project_dir: "/x/y"}} =
               Main.parse_args(["where", "--project-dir", "/x/y"])
    end

    test "where command without the flag" do
      assert {"where", [], _} = Main.parse_args(["where"])
    end
  end

  describe "run/2 — successful resolution paths" do
    test "reports :env source when FAMILIAR_PROJECT_DIR is set to a real project",
         %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "viaenv")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{env_getter: fn -> project end})
      result = Main.run({"where", [], %{}}, deps)

      assert {:ok, diag} = result
      assert diag.project_dir == Path.expand(project)
      assert diag.source == %{type: :env}
      assert diag.env == project
      assert diag.familiar_dir_exists == true
      assert diag.initialized == true
    end

    test "reports :walk_up source when cwd is deep inside a project", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "walkup")
      deep = Path.join([project, "lib", "mod", "sub"])
      File.mkdir_p!(Path.join(project, ".familiar"))
      File.mkdir_p!(deep)

      deps = base_deps(%{cwd_getter: fn -> deep end})
      result = Main.run({"where", [], %{}}, deps)

      assert {:ok, diag} = result
      assert diag.project_dir == Path.expand(project)
      assert match?(%{type: :walk_up, found_at: _}, diag.source)
      assert diag.source.found_at == Path.expand(project)
      assert diag.cwd == deep
      assert diag.initialized == true
    end

    test "reports :explicit source when --project-dir flag is passed", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "explicit")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps()
      result = Main.run({"where", [], %{project_dir: project}}, deps)

      assert {:ok, diag} = result
      assert diag.project_dir == Path.expand(project)
      assert diag.source == %{type: :explicit}
      assert diag.explicit == project
      assert diag.initialized == true
    end

    test "reports :cwd_fallback source but as an error when no .familiar/ is found",
         %{tmp_dir: tmp_dir} do
      # Per AC6 (Story 7.5-8): `fam where` must still produce a full
      # diagnostic when resolution fails, AND must exit non-zero. The
      # diagnostic is carried as the error details payload.
      bare = Path.join(tmp_dir, "bare")
      File.mkdir_p!(bare)

      deps = base_deps(%{cwd_getter: fn -> bare end})
      result = Main.run({"where", [], %{}}, deps)

      assert {:error, {:project_dir_unresolvable, diag}} = result
      assert diag.project_dir == Path.expand(bare)
      assert diag.source == %{type: :cwd_fallback}
      assert diag.familiar_dir_exists == false
      assert diag.initialized == false
      assert diag.resolved == false
    end
  end

  describe "run/2 — daemon status reporting" do
    test "shows daemon as stopped when daemon_status_fn returns :stopped",
         %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{cwd_getter: fn -> project end})
      {:ok, diag} = Main.run({"where", [], %{}}, deps)

      assert diag.daemon == :stopped
    end

    test "shows daemon as running when daemon_status_fn returns :running", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps =
        base_deps(%{
          cwd_getter: fn -> project end,
          daemon_status_fn: fn _opts -> {:running, %{pid: 12_345, port: 4000}} end
        })

      {:ok, diag} = Main.run({"where", [], %{}}, deps)
      assert diag.daemon == :running
      assert diag.daemon_info.pid == 12_345
    end
  end

  describe "run/2 — config.toml existence" do
    test "reports config.toml as existing when the file is present", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      familiar_dir = Path.join(project, ".familiar")
      File.mkdir_p!(familiar_dir)
      File.write!(Path.join(familiar_dir, "config.toml"), "")

      deps = base_deps(%{cwd_getter: fn -> project end})
      {:ok, diag} = Main.run({"where", [], %{}}, deps)

      assert diag.config_exists == true
    end

    test "reports config.toml as missing when absent", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{cwd_getter: fn -> project end})
      {:ok, diag} = Main.run({"where", [], %{}}, deps)

      assert diag.config_exists == false
    end
  end

  describe "text formatter renders a readable diagnostic dump" do
    test "includes all key diagnostic lines", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{cwd_getter: fn -> project end})
      {:ok, diag} = Main.run({"where", [], %{}}, deps)

      formatter = Main.text_formatter("where")
      rendered = formatter.(diag)

      assert rendered =~ "project_dir:"
      assert rendered =~ "source:"
      assert rendered =~ "cwd:"
      assert rendered =~ "env:"
      assert rendered =~ "explicit:"
      assert rendered =~ "familiar_dir:"
      assert rendered =~ "config:"
      assert rendered =~ "daemon:"
      assert rendered =~ Path.expand(project)
    end
  end

  describe "JSON mode — full envelope" do
    test "emits all fields in a data envelope including source shape",
         %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{cwd_getter: fn -> project end})
      result = Main.run({"where", [], %{}}, deps)
      json = Output.format(result, :json)
      decoded = Jason.decode!(json)

      assert is_map(decoded["data"])
      assert decoded["data"]["project_dir"] == Path.expand(project)
      assert decoded["data"]["initialized"] == true
      assert decoded["data"]["resolved"] == true
      assert decoded["data"]["daemon"] == "stopped"

      # Story 7.5-8: `source` is a JSON-encodable map — pin the contract
      # so third-party consumers see a stable shape.
      assert decoded["data"]["source"]["type"] == "walk_up"
      assert decoded["data"]["source"]["found_at"] == Path.expand(project)
    end

    test "source shape for :explicit source", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "exp")
      File.mkdir_p!(Path.join(project, ".familiar"))

      result = Main.run({"where", [], %{project_dir: project}}, base_deps())
      decoded = result |> Output.format(:json) |> Jason.decode!()

      assert decoded["data"]["source"]["type"] == "explicit"
      refute Map.has_key?(decoded["data"]["source"], "found_at")
    end
  end

  describe "run/2 — unresolvable error surfaces (AC6)" do
    test "returns {:error, :project_dir_unresolvable} when walk-up fails with no fallback target",
         %{tmp_dir: tmp_dir} do
      # cwd is a bare dir with no .familiar/ anywhere above it — strict
      # resolve should fail, `fam where` should return an error tuple.
      bare = Path.join(tmp_dir, "nowhere")
      File.mkdir_p!(bare)

      deps = base_deps(%{cwd_getter: fn -> bare end})
      result = Main.run({"where", [], %{}}, deps)

      assert {:error, {:project_dir_unresolvable, diag}} = result
      assert diag.resolved == false
      assert diag.project_dir == Path.expand(bare)
      assert diag.source == %{type: :cwd_fallback}
    end

    test "error result produces a non-zero exit code", %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "nowhere")
      File.mkdir_p!(bare)

      deps = base_deps(%{cwd_getter: fn -> bare end})
      result = Main.run({"where", [], %{}}, deps)

      assert Output.exit_code(result) == 1
    end

    test "error result renders in text mode via Output.format/3", %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "nowhere")
      File.mkdir_p!(bare)

      deps = base_deps(%{cwd_getter: fn -> bare end})
      result = Main.run({"where", [], %{}}, deps)
      rendered = Output.format(result, :text)

      # Error message body renders regardless of the text_formatter
      # for the "where" command — the error path goes through
      # error_message/2, not text_formatter/1.
      assert rendered =~ "Could not determine the Familiar project directory"
      assert rendered =~ "fam where"
    end

    test "error result JSON envelope has the :project_dir_unresolvable type",
         %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "nowhere")
      File.mkdir_p!(bare)

      deps = base_deps(%{cwd_getter: fn -> bare end})
      result = Main.run({"where", [], %{}}, deps)
      decoded = result |> Output.format(:json) |> Jason.decode!()

      assert decoded["error"]["type"] == "project_dir_unresolvable"
    end

    test "happy path (resolved: true) returns :ok and exit 0", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps = base_deps(%{cwd_getter: fn -> project end})
      result = Main.run({"where", [], %{}}, deps)

      assert {:ok, _diag} = result
      assert Output.exit_code(result) == 0
    end
  end

  describe "run/2 — edge cases in injected deps" do
    test "env_getter raising is handled gracefully", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps =
        base_deps(%{
          env_getter: fn -> raise "boom" end,
          cwd_getter: fn -> project end
        })

      assert {:ok, diag} = Main.run({"where", [], %{}}, deps)
      assert diag.env == nil
      assert diag.project_dir == Path.expand(project)
    end

    test "cwd_getter returning nil is handled gracefully" do
      deps =
        base_deps(%{
          cwd_getter: fn -> nil end
        })

      # Should not crash — normalize_cwd_value substitutes "(unknown)".
      result = Main.run({"where", [], %{}}, deps)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "daemon_status_fn returning a bare atom is preserved", %{tmp_dir: tmp_dir} do
      project = Path.join(tmp_dir, "proj")
      File.mkdir_p!(Path.join(project, ".familiar"))

      deps =
        base_deps(%{
          cwd_getter: fn -> project end,
          daemon_status_fn: fn _opts -> :running end
        })

      assert {:ok, diag} = Main.run({"where", [], %{}}, deps)
      assert diag.daemon == :running
    end
  end
end
