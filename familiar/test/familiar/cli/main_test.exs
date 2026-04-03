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

  describe "run/2 with auto-init" do
    test "auto-init triggers when no .familiar/ dir" do
      # When prerequisites fail, auto-init returns the prerequisite error
      prereq_deps =
        deps(
          prerequisites_fn: fn _opts ->
            {:error,
             {:prerequisites_failed, %{missing: ["ollama"], instructions: "Install Ollama"}}}
          end
        )

      result = Main.run({"health", [], %{}}, prereq_deps)
      assert {:error, {:prerequisites_failed, _}} = result
    end

    test "auto-init runs init then executes original command" do
      init_deps =
        deps(
          prerequisites_fn: fn _opts -> {:ok, %{}} end,
          init_fn: fn _opts ->
            Paths.ensure_familiar_dir!()
            {:ok, %{files_scanned: 1, entries_created: 1}}
          end,
          ensure_running_fn: fn _opts -> {:ok, 4000} end,
          health_fn: fn 4000 -> {:ok, %{status: "ok", version: "0.1.0"}} end
        )

      result = Main.run({"health", [], %{}}, init_deps)
      assert {:ok, %{status: "ok"}} = result
    end

    test "auto-init triggers for config command when no .familiar/" do
      init_deps =
        deps(
          prerequisites_fn: fn _opts -> {:ok, %{}} end,
          init_fn: fn _opts ->
            Paths.ensure_familiar_dir!()
            {:ok, %{files_scanned: 0, entries_created: 0}}
          end
        )

      result = Main.run({"config", [], %{}}, init_deps)
      # After auto-init, config returns defaults since no config.toml written
      assert {:ok, config} = result
      assert config.provider.chat_model == "llama3.2"
    end

    test "auto-init failure prevents original command" do
      fail_deps =
        deps(
          prerequisites_fn: fn _opts -> {:ok, %{}} end,
          init_fn: fn _opts -> {:error, {:init_failed, %{reason: "disk full"}}} end
        )

      result = Main.run({"health", [], %{}}, fail_deps)
      assert {:error, {:init_failed, %{reason: "disk full"}}} = result
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

  describe "run/2 with config command" do
    test "returns config from config.toml" do
      Paths.ensure_familiar_dir!()

      # Write a minimal config file
      config_path = Path.join(Paths.familiar_dir(), "config.toml")

      File.write!(config_path, """
      [provider]
      chat_model = "codellama"
      """)

      result = Main.run({"config", [], %{}}, deps())
      assert {:ok, config} = result
      assert config.provider.chat_model == "codellama"
      # Defaults filled in
      assert config.provider.base_url == "http://localhost:11434"
    end

    test "returns defaults when no config file" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"config", [], %{}}, deps())
      assert {:ok, config} = result
      assert config.provider.chat_model == "llama3.2"
    end

    test "returns error for invalid config" do
      Paths.ensure_familiar_dir!()

      config_path = Path.join(Paths.familiar_dir(), "config.toml")
      File.write!(config_path, "[provider]\ntimeout = -1")

      result = Main.run({"config", [], %{}}, deps())
      assert {:error, {:invalid_config, %{field: "provider.timeout"}}} = result
    end
  end

  describe "run/2 with search command" do
    test "returns search results" do
      Paths.ensure_familiar_dir!()

      search_deps =
        deps(
          search_fn: fn "auth query" ->
            {:ok,
             [
               %{
                 id: 1,
                 text: "Auth uses JWT tokens",
                 type: "convention",
                 source: "init_scan",
                 source_file: "lib/auth.ex",
                 distance: 0.1,
                 inserted_at: ~U[2026-04-01 00:00:00Z],
                 freshness: :fresh
               }
             ]}
          end
        )

      result = Main.run({"search", ["auth query"], %{raw: true}}, search_deps)
      assert {:ok, %{results: [_ | _], query: "auth query"}} = result
    end

    test "formats stale entries with [stale] indicator" do
      Paths.ensure_familiar_dir!()

      search_deps =
        deps(
          search_fn: fn "stale query" ->
            {:ok,
             [
               %{
                 id: 1,
                 text: "Stale knowledge",
                 type: "convention",
                 source: "init_scan",
                 source_file: "lib/old.ex",
                 distance: 0.1,
                 inserted_at: ~U[2026-04-01 00:00:00Z],
                 freshness: :stale
               }
             ]}
          end
        )

      result = Main.run({"search", ["stale query"], %{raw: true}}, search_deps)
      assert {:ok, %{results: [_ | _]}} = result
    end

    test "returns usage error when no query provided" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"search", [], %{}}, deps())
      assert {:error, {:usage_error, %{message: msg}}} = result
      assert msg =~ "search"
    end

    test "propagates search errors" do
      Paths.ensure_familiar_dir!()

      err_deps =
        deps(
          search_fn: fn _query ->
            {:error, {:provider_unavailable, %{provider: :ollama}}}
          end
        )

      result = Main.run({"search", ["query"], %{raw: true}}, err_deps)
      assert {:error, {:provider_unavailable, _}} = result
    end
  end

  describe "run/2 with entry command" do
    test "returns entry detail for valid ID" do
      Paths.ensure_familiar_dir!()

      mock_entry = %Familiar.Knowledge.Entry{
        id: 42,
        text: "Auth uses JWT",
        type: "fact",
        source: "init_scan",
        source_file: "lib/auth.ex",
        metadata: ~s({"key": "value"}),
        inserted_at: ~U[2026-04-01 00:00:00Z],
        updated_at: ~U[2026-04-01 12:00:00Z]
      }

      entry_deps =
        deps(
          fetch_entry_fn: fn 42 -> {:ok, mock_entry} end,
          freshness_fn: fn [^mock_entry], _opts ->
            {:ok, %{fresh: [mock_entry], stale: [], deleted: [], warnings: []}}
          end
        )

      result = Main.run({"entry", ["42"], %{}}, entry_deps)
      assert {:ok, entry} = result
      assert entry.id == 42
      assert entry.text == "Auth uses JWT"
      assert entry.type == "fact"
      assert entry.metadata == %{"key" => "value"}
      assert entry.freshness == :fresh
    end

    test "returns not_found for missing entry" do
      Paths.ensure_familiar_dir!()

      entry_deps =
        deps(fetch_entry_fn: fn 999 -> {:error, {:not_found, %{id: 999}}} end)

      result = Main.run({"entry", ["999"], %{}}, entry_deps)
      assert {:error, {:not_found, %{id: 999}}} = result
    end

    test "returns usage error for non-numeric ID" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"entry", ["abc"], %{}}, deps())
      assert {:error, {:usage_error, %{message: msg}}} = result
      assert msg =~ "Invalid entry ID"
    end

    test "returns usage error when no ID provided" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"entry", [], %{}}, deps())
      assert {:error, {:usage_error, _}} = result
    end
  end

  describe "run/2 with edit command" do
    test "edits entry and returns result" do
      Paths.ensure_familiar_dir!()

      edit_deps =
        deps(
          fetch_entry_fn: fn 42 ->
            {:ok,
             %Familiar.Knowledge.Entry{
               id: 42,
               text: "Old text",
               type: "fact",
               source: "init_scan",
               source_file: "lib/auth.ex",
               metadata: "{}",
               inserted_at: ~U[2026-04-01 00:00:00Z],
               updated_at: ~U[2026-04-01 00:00:00Z]
             }}
          end,
          update_entry_fn: fn _entry, %{text: "New knowledge text", source: "user"} ->
            {:ok,
             %Familiar.Knowledge.Entry{
               id: 42,
               text: "New knowledge text",
               type: "fact",
               source: "user",
               source_file: "lib/auth.ex",
               metadata: "{}",
               inserted_at: ~U[2026-04-01 00:00:00Z],
               updated_at: ~U[2026-04-02 00:00:00Z]
             }}
          end
        )

      result = Main.run({"edit", ["42", "New", "knowledge", "text"], %{}}, edit_deps)
      assert {:ok, %{id: 42, text: "New knowledge text", status: "edited"}} = result
    end

    test "returns not_found for missing entry" do
      Paths.ensure_familiar_dir!()

      edit_deps =
        deps(fetch_entry_fn: fn 999 -> {:error, {:not_found, %{id: 999}}} end)

      result = Main.run({"edit", ["999", "text"], %{}}, edit_deps)
      assert {:error, {:not_found, _}} = result
    end

    test "returns usage error when no text provided" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"edit", ["42"], %{}}, deps())
      assert {:error, {:usage_error, _}} = result
    end

    test "returns usage error when no args" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"edit", [], %{}}, deps())
      assert {:error, {:usage_error, _}} = result
    end
  end

  describe "run/2 with delete command" do
    test "deletes entry and returns result" do
      Paths.ensure_familiar_dir!()

      delete_deps =
        deps(
          fetch_entry_fn: fn 42 ->
            {:ok,
             %Familiar.Knowledge.Entry{
               id: 42,
               text: "To delete",
               type: "fact",
               source: "init_scan",
               source_file: "lib/auth.ex",
               metadata: "{}",
               inserted_at: ~U[2026-04-01 00:00:00Z],
               updated_at: ~U[2026-04-01 00:00:00Z]
             }}
          end,
          delete_entry_fn: fn _entry -> :ok end
        )

      result = Main.run({"delete", ["42"], %{}}, delete_deps)
      assert {:ok, %{id: 42, status: "deleted"}} = result
    end

    test "returns not_found for missing entry" do
      Paths.ensure_familiar_dir!()

      delete_deps =
        deps(fetch_entry_fn: fn 999 -> {:error, {:not_found, %{id: 999}}} end)

      result = Main.run({"delete", ["999"], %{}}, delete_deps)
      assert {:error, {:not_found, _}} = result
    end

    test "returns usage error when no ID" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"delete", [], %{}}, deps())
      assert {:error, {:usage_error, _}} = result
    end
  end

  describe "run/2 with context command" do
    test "context --refresh calls refresh function" do
      Paths.ensure_familiar_dir!()

      ctx_deps =
        deps(
          refresh_fn: fn _dir, _opts ->
            {:ok, %{scanned: 5, updated: 2, created: 1, removed: 0, preserved: 1}}
          end
        )

      result = Main.run({"context", [], %{refresh: true}}, ctx_deps)
      assert {:ok, %{scanned: 5, updated: 2}} = result
    end

    test "context --refresh with path passes filter" do
      Paths.ensure_familiar_dir!()

      ctx_deps =
        deps(
          refresh_fn: fn _dir, opts ->
            assert Keyword.get(opts, :path) == "lib/auth"
            {:ok, %{scanned: 1, updated: 1, created: 0, removed: 0, preserved: 0}}
          end
        )

      result = Main.run({"context", ["lib/auth"], %{refresh: true}}, ctx_deps)
      assert {:ok, %{scanned: 1}} = result
    end

    test "context --compact calls compact function" do
      Paths.ensure_familiar_dir!()

      ctx_deps =
        deps(
          compact_candidates_fn: fn _opts ->
            {:ok, %{candidates: []}}
          end
        )

      result = Main.run({"context", [], %{compact: true}}, ctx_deps)
      assert {:ok, %{candidates: []}} = result
    end

    test "context --compact --apply merges specified candidates" do
      Paths.ensure_familiar_dir!()

      ctx_deps =
        deps(
          compact_candidates_fn: fn _opts ->
            {:ok,
             %{
               candidates: [
                 %{id_a: 1, id_b: 2, text_a: "A", text_b: "B", type: "fact", distance: 0.1}
               ]
             }}
          end,
          compact_fn: fn [{1, 2}], _opts ->
            {:ok, %{merged: 1, failed: 0}}
          end
        )

      result = Main.run({"context", [], %{compact: true, apply: "1"}}, ctx_deps)
      assert {:ok, %{merged: 1}} = result
    end

    test "context without flags returns usage error" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"context", [], %{}}, deps())
      assert {:error, {:usage_error, _}} = result
    end
  end

  describe "run/2 with backup command" do
    test "creates a backup" do
      Paths.ensure_familiar_dir!()

      backup_deps =
        deps(
          backup_fn: fn _opts ->
            {:ok, %{path: "/backups/familiar-20260402T120000.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}}
          end
        )

      result = Main.run({"backup", [], %{}}, backup_deps)
      assert {:ok, %{path: _, size: 4096}} = result
    end

    test "propagates backup errors" do
      Paths.ensure_familiar_dir!()

      backup_deps =
        deps(backup_fn: fn _opts -> {:error, {:backup_failed, %{reason: :disk_full}}} end)

      result = Main.run({"backup", [], %{}}, backup_deps)
      assert {:error, {:backup_failed, _}} = result
    end
  end

  describe "run/2 with restore command" do
    test "lists backups when no args" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts ->
            {:ok, [%{path: "/b/f.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}]}
          end
        )

      result = Main.run({"restore", [], %{}}, restore_deps)
      assert {:ok, [%{filename: "familiar-20260402T120000.db"}]} = result
    end

    test "restores specific backup with confirmation" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts ->
            {:ok, [%{path: "/b/familiar-20260402T120000.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}]}
          end,
          restore_fn: fn _path, _opts -> :ok end,
          confirm_fn: fn _prompt -> "y\n" end
        )

      result = Main.run({"restore", ["20260402T120000"], %{}}, restore_deps)
      assert {:ok, %{restored: "familiar-20260402T120000.db", status: "restored"}} = result
    end

    test "returns cancelled when user declines" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts ->
            {:ok, [%{path: "/b/f.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}]}
          end,
          confirm_fn: fn _prompt -> "n\n" end
        )

      result = Main.run({"restore", ["20260402T120000"], %{}}, restore_deps)
      assert {:error, {:cancelled, %{}}} = result
    end

    test "skips confirmation with --force flag" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts ->
            {:ok, [%{path: "/b/f.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}]}
          end,
          restore_fn: fn _path, _opts -> :ok end
        )

      result = Main.run({"restore", ["20260402T120000"], %{force: true}}, restore_deps)
      assert {:ok, %{restored: _, status: "restored"}} = result
    end

    test "skips confirmation in --json mode" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts ->
            {:ok, [%{path: "/b/f.db", filename: "familiar-20260402T120000.db", size: 4096, timestamp: "20260402T120000"}]}
          end,
          restore_fn: fn _path, _opts -> :ok end
        )

      result = Main.run({"restore", ["20260402T120000"], %{json: true}}, restore_deps)
      assert {:ok, %{status: "restored"}} = result
    end

    test "returns not_found for unknown timestamp" do
      Paths.ensure_familiar_dir!()

      restore_deps =
        deps(
          backup_list_fn: fn _opts -> {:ok, []} end
        )

      result = Main.run({"restore", ["99990101T000000"], %{force: true}}, restore_deps)
      assert {:error, {:not_found, %{timestamp: "99990101T000000"}}} = result
    end
  end

  describe "run/2 with status command" do
    test "returns knowledge health metrics" do
      Paths.ensure_familiar_dir!()

      status_deps =
        deps(
          context_health_fn: fn _opts ->
            {:ok,
             %{
               entry_count: 10,
               types: %{"fact" => 5},
               staleness_ratio: 0.0,
               last_refresh: nil,
               backup: %{last: nil, count: 0},
               signal: :amber
             }}
          end
        )

      result = Main.run({"status", [], %{}}, status_deps)
      assert {:ok, %{entry_count: 10, signal: :amber, command: "status"}} = result
    end
  end

  describe "run/2 with context --health" do
    test "returns health metrics" do
      Paths.ensure_familiar_dir!()

      health_deps =
        deps(
          context_health_fn: fn _opts ->
            {:ok,
             %{
               entry_count: 42,
               types: %{"fact" => 15, "convention" => 10},
               staleness_ratio: 0.05,
               last_refresh: ~U[2026-04-02 10:00:00Z],
               backup: %{last: "20260402T090000", count: 3},
               signal: :green
             }}
          end
        )

      result = Main.run({"context", [], %{health: true}}, health_deps)
      assert {:ok, %{entry_count: 42, signal: :green}} = result
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

  describe "parse_args/1 for plan command" do
    test "parses plan with description" do
      assert {"plan", ["add", "user", "accounts"], %{}} = Main.parse_args(["plan", "add", "user", "accounts"])
    end

    test "parses plan --resume" do
      assert {"plan", [], %{resume: true}} = Main.parse_args(["plan", "--resume"])
    end

    test "parses plan --resume --session 42" do
      assert {"plan", [], %{resume: true, session: 42}} = Main.parse_args(["plan", "--resume", "--session", "42"])
    end

    test "parses search --raw" do
      assert {"search", ["query"], %{raw: true}} = Main.parse_args(["search", "--raw", "query"])
    end
  end

  describe "run/2 with plan command" do
    test "returns not_implemented for plan with description" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"plan", ["add", "user", "accounts"], %{}}, deps())
      assert {:error, {:not_implemented, %{message: msg}}} = result
      assert msg =~ "workflow runner"
    end

    test "returns not_implemented for plan --resume" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"plan", [], %{resume: true}}, deps())
      assert {:error, {:not_implemented, _}} = result
    end

    test "returns not_implemented for plan with no args" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"plan", [], %{}}, deps())
      assert {:error, {:not_implemented, _}} = result
    end
  end

  describe "run/2 with spec command" do
    test "returns not_implemented" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"spec", ["1"], %{}}, deps())
      assert {:error, {:not_implemented, %{message: msg}}} = result
      assert msg =~ "workflow"
    end
  end

  # -- Test helpers --

  describe "run/2 with generate-spec command" do
    test "returns not_implemented" do
      Paths.ensure_familiar_dir!()

      result = Main.run({"generate-spec", ["42"], %{}}, deps())
      assert {:error, {:not_implemented, %{message: msg}}} = result
      assert msg =~ "workflow runner"
    end

    test "parses generate-spec command" do
      assert {"generate-spec", ["42"], %{}} = Main.parse_args(["generate-spec", "42"])
    end
  end

  defp deps(overrides \\ []) do
    base = %{
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
        Keyword.get(overrides, :version_compatible_fn, fn _cli, _daemon -> true end),
      prerequisites_fn:
        Keyword.get(overrides, :prerequisites_fn, fn _opts ->
          {:error,
           {:prerequisites_failed, %{missing: ["ollama"], instructions: "Install Ollama"}}}
        end),
      init_fn:
        Keyword.get(overrides, :init_fn, fn _opts ->
          {:ok, %{files_scanned: 0, entries_created: 0}}
        end)
    }

    # Merge any extra keys (e.g., search_fn, conventions_fn)
    extras =
      overrides
      |> Keyword.drop(Map.keys(base))
      |> Map.new()

    Map.merge(base, extras)
  end
end
