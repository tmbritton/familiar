defmodule Familiar.Knowledge.InitCleanupTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Familiar.Knowledge.InitScanner

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "atomic cleanup" do
    test "run_with_cleanup deletes .familiar/ on error", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          # Create the dir during init
          File.mkdir_p!(familiar_dir)
          File.write!(Path.join(familiar_dir, "test.txt"), "data")
          {:error, {:init_failed, %{reason: "simulated failure"}}}
        end)

      assert {:error, {:init_failed, _}} = result
      refute File.dir?(familiar_dir)
    end

    test "run_with_cleanup preserves .familiar/ on success", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          File.mkdir_p!(familiar_dir)
          File.write!(Path.join(familiar_dir, "test.txt"), "data")
          {:ok, %{files_scanned: 0, entries_created: 0}}
        end)

      assert {:ok, _} = result
      assert File.dir?(familiar_dir)
    end

    test "run_with_cleanup deletes .familiar/ on exception", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          File.mkdir_p!(familiar_dir)
          raise "unexpected crash"
        end)

      assert {:error, {:init_failed, %{reason: _}}} = result
      refute File.dir?(familiar_dir)
    end

    test "run_with_cleanup deletes .familiar/ on exit", %{tmp_dir: tmp_dir} do
      familiar_dir = Path.join(tmp_dir, ".familiar")

      result =
        InitScanner.run_with_cleanup(tmp_dir, fn ->
          File.mkdir_p!(familiar_dir)
          exit(:shutdown)
        end)

      assert {:error, {:init_failed, %{reason: _}}} = result
      refute File.dir?(familiar_dir)
    end
  end
end
