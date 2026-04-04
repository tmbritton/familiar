defmodule Familiar.Execution.ToolsTest do
  use ExUnit.Case, async: false

  import Mox

  alias Familiar.Execution.ToolRegistry
  alias Familiar.Execution.Tools

  setup :verify_on_exit!

  setup do
    Mox.set_mox_global()
    :ok
  end

  defp ctx(overrides \\ %{}) do
    Map.merge(%{agent_id: "agent_1", role: "test", conversation_id: "conv_1"}, overrides)
  end

  # == read_file ==

  describe "read_file/2" do
    test "returns file content on success" do
      Familiar.System.FileSystemMock
      |> expect(:read, fn "/project/lib/foo.ex" -> {:ok, "defmodule Foo do\nend"} end)

      assert {:ok, %{content: "defmodule Foo do\nend"}} =
               Tools.read_file(%{path: "/project/lib/foo.ex"}, ctx())
    end

    test "returns error for missing file" do
      Familiar.System.FileSystemMock
      |> expect(:read, fn "/missing.ex" ->
        {:error, {:file_error, %{path: "/missing.ex", reason: :enoent}}}
      end)

      assert {:error, {:file_error, _}} = Tools.read_file(%{path: "/missing.ex"}, ctx())
    end

    test "supports string keys" do
      Familiar.System.FileSystemMock
      |> expect(:read, fn "foo.ex" -> {:ok, "content"} end)

      assert {:ok, %{content: "content"}} = Tools.read_file(%{"path" => "foo.ex"}, ctx())
    end

    test "returns error when path arg is missing" do
      assert {:error, {:missing_arg, %{arg: :path}}} = Tools.read_file(%{}, ctx())
    end
  end

  # == write_file ==

  describe "write_file/2" do
    test "writes content and returns path" do
      Familiar.System.FileSystemMock
      |> expect(:write, fn "/project/lib/bar.ex", "defmodule Bar" -> :ok end)

      assert {:ok, %{path: "/project/lib/bar.ex"}} =
               Tools.write_file(%{path: "/project/lib/bar.ex", content: "defmodule Bar"}, ctx())
    end

    test "returns error on write failure" do
      Familiar.System.FileSystemMock
      |> expect(:write, fn _p, _c -> {:error, {:file_error, %{reason: :eacces}}} end)

      assert {:error, {:file_error, _}} =
               Tools.write_file(%{path: "/readonly.ex", content: "x"}, ctx())
    end

    test "defaults to empty content" do
      Familiar.System.FileSystemMock
      |> expect(:write, fn "new.ex", "" -> :ok end)

      assert {:ok, %{path: "new.ex"}} = Tools.write_file(%{path: "new.ex"}, ctx())
    end

    test "returns error when path arg is missing" do
      assert {:error, {:missing_arg, %{arg: :path}}} = Tools.write_file(%{content: "x"}, ctx())
    end
  end

  # == delete_file ==

  describe "delete_file/2" do
    test "deletes file and returns path" do
      Familiar.System.FileSystemMock
      |> expect(:delete, fn "/project/old.ex" -> :ok end)

      assert {:ok, %{path: "/project/old.ex"}} =
               Tools.delete_file(%{path: "/project/old.ex"}, ctx())
    end

    test "returns error when file doesn't exist" do
      Familiar.System.FileSystemMock
      |> expect(:delete, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)

      assert {:error, {:file_error, _}} = Tools.delete_file(%{path: "/gone.ex"}, ctx())
    end

    test "returns error when path arg is missing" do
      assert {:error, {:missing_arg, %{arg: :path}}} = Tools.delete_file(%{}, ctx())
    end
  end

  # == list_files ==

  describe "list_files/2" do
    test "returns file list" do
      Familiar.System.FileSystemMock
      |> expect(:ls, fn "/project/lib" -> {:ok, ["foo.ex", "bar.ex"]} end)

      assert {:ok, %{files: ["foo.ex", "bar.ex"]}} =
               Tools.list_files(%{path: "/project/lib"}, ctx())
    end

    test "returns error for invalid path" do
      Familiar.System.FileSystemMock
      |> expect(:ls, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)

      assert {:error, {:file_error, _}} = Tools.list_files(%{path: "/nope"}, ctx())
    end

    test "defaults to current directory" do
      Familiar.System.FileSystemMock
      |> expect(:ls, fn "." -> {:ok, ["mix.exs"]} end)

      assert {:ok, %{files: ["mix.exs"]}} = Tools.list_files(%{}, ctx())
    end
  end

  # == search_files ==

  describe "search_files/2" do
    test "returns matching lines from files" do
      Familiar.System.FileSystemMock
      |> stub(:ls, fn
        "lib/" -> {:ok, ["foo.ex", "bar.ex"]}
      end)

      Familiar.System.FileSystemMock
      |> stub(:read, fn
        "lib/foo.ex" -> {:ok, "defmodule Foo do\n  def hello, do: :ok\nend"}
        "lib/bar.ex" -> {:ok, "defmodule Bar do\nend"}
      end)

      assert {:ok, %{matches: matches}} =
               Tools.search_files(%{path: "lib/", pattern: "defmodule"}, ctx())

      assert length(matches) == 2
      assert Enum.all?(matches, &(&1.content =~ "defmodule"))
    end

    test "searches recursively into subdirectories" do
      Familiar.System.FileSystemMock
      |> stub(:ls, fn
        "lib/" -> {:ok, ["foo.ex", "sub"]}
        "lib/sub" -> {:ok, ["deep.ex"]}
        _ -> {:error, {:file_error, %{reason: :enoent}}}
      end)

      Familiar.System.FileSystemMock
      |> stub(:read, fn
        "lib/foo.ex" -> {:ok, "defmodule Foo"}
        # "lib/sub" is a dir — read fails, triggers recursive ls
        "lib/sub" -> {:error, {:file_error, %{reason: :eisdir}}}
        "lib/sub/deep.ex" -> {:ok, "defmodule Deep"}
        _ -> {:error, {:file_error, %{reason: :enoent}}}
      end)

      assert {:ok, %{matches: matches}} =
               Tools.search_files(%{path: "lib/", pattern: "defmodule"}, ctx())

      paths = Enum.map(matches, & &1.path)
      assert "lib/foo.ex" in paths
      assert "lib/sub/deep.ex" in paths
    end

    test "returns empty matches when no hits" do
      Familiar.System.FileSystemMock
      |> stub(:ls, fn "lib/" -> {:ok, ["foo.ex"]} end)
      |> stub(:read, fn "lib/foo.ex" -> {:ok, "hello world"} end)

      assert {:ok, %{matches: []}} =
               Tools.search_files(%{path: "lib/", pattern: "nonexistent"}, ctx())
    end

    test "returns error when pattern is missing" do
      assert {:error, {:missing_arg, %{arg: :pattern}}} =
               Tools.search_files(%{path: "lib/"}, ctx())
    end

    test "returns error when pattern is empty string" do
      assert {:error, {:invalid_args, _}} =
               Tools.search_files(%{path: "lib/", pattern: ""}, ctx())
    end

    test "returns error when directory listing fails" do
      Familiar.System.FileSystemMock
      |> expect(:ls, fn _p -> {:error, {:file_error, %{reason: :enoent}}} end)

      assert {:ok, %{matches: []}} =
               Tools.search_files(%{path: "/nope", pattern: "x"}, ctx())
    end

    test "skips unreadable files" do
      Familiar.System.FileSystemMock
      |> stub(:ls, fn "lib/" -> {:ok, ["good.ex", "bad.ex"]} end)
      |> stub(:read, fn
        "lib/good.ex" -> {:ok, "defmodule Good"}
        "lib/bad.ex" -> {:error, {:file_error, %{reason: :eacces}}}
      end)

      # bad.ex read fails and is not a directory (ls also fails), so it's skipped
      Familiar.System.FileSystemMock
      |> stub(:ls, fn
        "lib/" -> {:ok, ["good.ex", "bad.ex"]}
        "lib/bad.ex" -> {:error, {:file_error, %{reason: :enotdir}}}
        _ -> {:error, {:file_error, %{reason: :enoent}}}
      end)

      assert {:ok, %{matches: [match]}} =
               Tools.search_files(%{path: "lib/", pattern: "defmodule"}, ctx())

      assert match.path == "lib/good.ex"
    end
  end

  # == run_command ==

  describe "run_command/2" do
    test "runs command and returns output" do
      Familiar.System.ShellMock
      |> expect(:cmd, fn "mix", ["test", "--trace"], [] ->
        {:ok, %{output: "3 tests, 0 failures", exit_code: 0}}
      end)

      assert {:ok, %{output: "3 tests, 0 failures", exit_code: 0}} =
               Tools.run_command(%{command: "mix test --trace"}, ctx())
    end

    test "returns non-zero exit code" do
      Familiar.System.ShellMock
      |> expect(:cmd, fn "mix", ["test"], [] ->
        {:ok, %{output: "1 failure", exit_code: 1}}
      end)

      assert {:ok, %{exit_code: 1}} = Tools.run_command(%{command: "mix test"}, ctx())
    end

    test "returns error on shell failure" do
      Familiar.System.ShellMock
      |> expect(:cmd, fn _e, _a, _o -> {:error, {:shell_error, %{reason: :enoent}}} end)

      assert {:error, {:shell_error, _}} =
               Tools.run_command(%{command: "nonexistent_cmd"}, ctx())
    end

    test "returns error when command is missing" do
      assert {:error, {:missing_arg, %{arg: :command}}} = Tools.run_command(%{}, ctx())
    end

    test "returns error when command is empty" do
      assert {:error, {:invalid_args, _}} = Tools.run_command(%{command: ""}, ctx())
    end

    test "returns error when command is whitespace only" do
      assert {:error, {:invalid_args, _}} = Tools.run_command(%{command: "   "}, ctx())
    end
  end

  # == spawn_agent ==

  describe "spawn_agent/2" do
    test "returns error when role is missing" do
      assert {:error, {:missing_arg, %{arg: :role}}} =
               Tools.spawn_agent(%{task: "do something"}, ctx())
    end

    test "returns error when task is missing" do
      assert {:error, {:missing_arg, %{arg: :task}}} =
               Tools.spawn_agent(%{role: "coder"}, ctx())
    end
  end

  # == run_workflow ==

  describe "run_workflow/2" do
    test "returns error when path is missing" do
      assert {:error, {:missing_arg, %{arg: :path}}} =
               Tools.run_workflow(%{task: "do something"}, ctx())
    end

    test "returns error when task is missing" do
      assert {:error, {:missing_arg, %{arg: :task}}} =
               Tools.run_workflow(%{path: "workflow.md"}, ctx())
    end

    test "returns error when workflow depth exceeded" do
      context = ctx(%{workflow_depth: 5})

      assert {:error, {:workflow_depth_exceeded, %{max: 5, depth: 5}}} =
               Tools.run_workflow(%{path: "workflow.md", task: "do it"}, context)
    end

    test "returns error when path is outside project directory" do
      assert {:error, {:path_outside_project, _}} =
               Tools.run_workflow(%{path: "/etc/evil.md", task: "read secrets"}, ctx())
    end

    test "returns error when path is not a .md file" do
      assert {:error, {:invalid_workflow_path, %{reason: "must be a .md file"}}} =
               Tools.run_workflow(%{path: "workflow.yaml", task: "do it"}, ctx())
    end
  end

  # == monitor_agents ==

  describe "monitor_agents/2" do
    test "returns list of agents" do
      assert {:ok, %{agents: agents}} = Tools.monitor_agents(%{}, ctx())
      assert is_list(agents)
    end
  end

  # == broadcast_status ==

  describe "broadcast_status/2" do
    test "broadcasts and returns ok" do
      assert {:ok, %{status: "broadcast"}} =
               Tools.broadcast_status(%{message: "50% complete"}, ctx())
    end

    test "works with string keys" do
      assert {:ok, %{status: "broadcast"}} =
               Tools.broadcast_status(%{"message" => "done"}, ctx())
    end
  end

  # == signal_ready_stub ==

  describe "signal_ready_stub/2" do
    test "returns no_workflow" do
      assert {:ok, %{status: "no_workflow"}} = Tools.signal_ready_stub(%{}, ctx())
    end
  end

  # == Registration ==

  describe "registration" do
    test "all builtin tools are registered with real implementations" do
      expected = [
        :read_file,
        :write_file,
        :delete_file,
        :list_files,
        :search_files,
        :run_command,
        :spawn_agent,
        :run_workflow,
        :monitor_agents,
        :broadcast_status,
        :signal_ready
      ]

      registered = ToolRegistry.list_tools()
      registered_names = Enum.map(registered, & &1.name)

      for name <- expected do
        assert name in registered_names, "Expected tool #{name} to be registered"
      end
    end
  end
end
