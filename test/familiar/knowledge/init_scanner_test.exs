defmodule Familiar.Knowledge.InitScannerTest do
  use Familiar.DataCase, async: false
  use Familiar.MockCase

  alias Familiar.Knowledge.InitScanner

  @moduletag :tmp_dir

  # Use real filesystem since these tests create actual files on disk
  @fs Familiar.System.LocalFileSystem

  setup %{tmp_dir: tmp_dir} do
    Application.put_env(:familiar, :project_dir, tmp_dir)
    on_exit(fn -> Application.delete_env(:familiar, :project_dir) end)
    :ok
  end

  describe "scan_files/1" do
    test "walks directory and classifies files", %{tmp_dir: tmp_dir} do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do end")
      create_file(tmp_dir, "lib/app/server.ex", "defmodule App.Server do end")
      create_file(tmp_dir, "test/app_test.exs", "defmodule AppTest do end")
      create_file(tmp_dir, "README.md", "# App")
      create_file(tmp_dir, "mix.exs", "defmodule App.MixProject do end")

      create_file(tmp_dir, "_build/dev/lib/app.beam", "binary")
      create_file(tmp_dir, "deps/phoenix/lib/phoenix.ex", "defmodule Phoenix do end")
      create_file(tmp_dir, ".git/config", "[core]")

      assert {:ok, files, 0} = InitScanner.scan_files(tmp_dir, file_system: @fs)
      paths = Enum.map(files, & &1.relative_path)

      assert "lib/app.ex" in paths
      assert "lib/app/server.ex" in paths
      assert "test/app_test.exs" in paths
      assert "README.md" in paths
      assert "mix.exs" in paths

      refute Enum.any?(paths, &String.starts_with?(&1, "_build/"))
      refute Enum.any?(paths, &String.starts_with?(&1, "deps/"))
      refute Enum.any?(paths, &String.starts_with?(&1, ".git/"))
    end

    test "returns empty list for empty project", %{tmp_dir: tmp_dir} do
      assert {:ok, [], 0} = InitScanner.scan_files(tmp_dir, file_system: @fs)
    end

    test "prioritizes when over 500 files", %{tmp_dir: tmp_dir} do
      for i <- 1..300 do
        create_file(tmp_dir, "lib/mod#{i}.ex", "defmodule Mod#{i} do end")
      end

      for i <- 1..210 do
        create_file(tmp_dir, "docs/page#{i}.md", "# Page #{i}")
      end

      assert {:ok, files, deferred} =
               InitScanner.scan_files(tmp_dir, max_files: 200, file_system: @fs)

      assert length(files) <= 200
      assert deferred > 0

      source_count = Enum.count(files, &String.ends_with?(&1.relative_path, ".ex"))
      doc_count = Enum.count(files, &String.ends_with?(&1.relative_path, ".md"))
      assert source_count > doc_count
    end

    test "includes file content", %{tmp_dir: tmp_dir} do
      content = "defmodule App do\n  def hello, do: :world\nend"
      create_file(tmp_dir, "lib/app.ex", content)

      {:ok, [file], 0} = InitScanner.scan_files(tmp_dir, file_system: @fs)
      assert file.content == content
      assert file.relative_path == "lib/app.ex"
    end

    test "skips unreadable files gracefully", %{tmp_dir: tmp_dir} do
      create_file(tmp_dir, "lib/good.ex", "defmodule Good do end")
      create_file(tmp_dir, "lib/bad.ex", "defmodule Bad do end")
      File.chmod!(Path.join(tmp_dir, "lib/bad.ex"), 0o000)

      {:ok, files, 0} = InitScanner.scan_files(tmp_dir, file_system: @fs)
      paths = Enum.map(files, & &1.relative_path)

      assert "lib/good.ex" in paths
      assert files != []
    after
      bad_path = Path.join(tmp_dir, "lib/bad.ex")
      if File.exists?(bad_path), do: File.chmod!(bad_path, 0o644)
    end
  end

  describe "run/1 full pipeline" do
    test "runs scan, extract, discover, embed pipeline", %{tmp_dir: tmp_dir} do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do\n  def hello, do: :world\nend")

      # LLM called for extraction + convention discovery
      Mox.expect(Familiar.Providers.LLMMock, :chat, 2, fn messages, _opts ->
        prompt = hd(messages).content

        if prompt =~ "conventions" do
          {:ok,
           %{
             content:
               Jason.encode!([
                 %{
                   "type" => "convention",
                   "text" => "Uses pattern matching",
                   "evidence_count" => 1,
                   "evidence_total" => 1
                 }
               ])
           }}
        else
          {:ok,
           %{
             content:
               Jason.encode!([
                 %{
                   "type" => "file_summary",
                   "text" => "App module defines a hello function",
                   "source_file" => "lib/app.ex"
                 }
               ])
           }}
        end
      end)

      # Embedder called for all entries (extraction + structural conventions + LLM conventions)
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        assert is_binary(text)
        {:ok, List.duplicate(0.1, 768)}
      end)

      # Shell called for command validation (no mix.exs so unknown language → skip)
      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned >= 1
      assert summary.entries_created >= 1
      assert summary.conventions_discovered >= 1
      assert summary.deferred == 0
    end

    test "returns warning when no source files found", %{tmp_dir: tmp_dir} do
      create_file(tmp_dir, "mix.lock", "lockfile")

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned == 0
      assert summary.entries_created == 0
      assert summary.warning =~ "No source files"
    end

    test "succeeds with empty project directory", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, ".familiar"))
      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned == 0
      assert summary.entries_created == 0
    end

    test "handles LLM extraction failure gracefully", %{tmp_dir: tmp_dir} do
      create_file(tmp_dir, "lib/app.ex", "defmodule App do end")

      # Both extraction and convention discovery LLM calls fail
      Mox.expect(Familiar.Providers.LLMMock, :chat, 2, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{reason: :timeout}}}
      end)

      # Structural conventions still get embedded
      Mox.stub(Familiar.Knowledge.EmbedderMock, :embed, fn text ->
        assert is_binary(text)
        {:ok, List.duplicate(0.1, 768)}
      end)

      result = InitScanner.run(tmp_dir, progress_fn: fn _msg -> :ok end, file_system: @fs)

      assert {:ok, summary} = result
      assert summary.files_scanned == 1
      assert summary.extraction_warnings =~ "could not be analyzed"
      # Structural conventions still discovered even when LLM fails
      assert summary.conventions_discovered >= 1
    end
  end

  # -- Test Helpers --

  defp create_file(base, relative_path, content) do
    full_path = Path.join(base, relative_path)
    full_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(full_path, content)
  end
end
