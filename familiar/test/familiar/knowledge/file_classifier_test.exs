defmodule Familiar.Knowledge.FileClassifierTest do
  use ExUnit.Case, async: true

  alias Familiar.Knowledge.FileClassifier

  describe "classify/2" do
    test "skips .git directory" do
      assert :skip = FileClassifier.classify(".git/config")
    end

    test "skips node_modules directory" do
      assert :skip = FileClassifier.classify("node_modules/express/index.js")
    end

    test "skips _build directory" do
      assert :skip = FileClassifier.classify("_build/dev/lib/familiar/ebin/Elixir.beam")
    end

    test "skips deps directory" do
      assert :skip = FileClassifier.classify("deps/phoenix/lib/phoenix.ex")
    end

    test "skips vendor directory" do
      assert :skip = FileClassifier.classify("vendor/github.com/lib/pq/conn.go")
    end

    test "skips .elixir_ls directory" do
      assert :skip = FileClassifier.classify(".elixir_ls/build/test/lib/familiar")
    end

    test "skips .familiar directory" do
      assert :skip = FileClassifier.classify(".familiar/daemon.json")
    end

    test "skips __pycache__ directory" do
      assert :skip = FileClassifier.classify("src/__pycache__/main.cpython-311.pyc")
    end

    test "skips target directory" do
      assert :skip = FileClassifier.classify("target/debug/binary")
    end

    test "skips dist directory" do
      assert :skip = FileClassifier.classify("dist/bundle.js")
    end

    test "skips build directory" do
      assert :skip = FileClassifier.classify("build/output.js")
    end

    test "skips .beam files" do
      assert :skip = FileClassifier.classify("lib/familiar.beam")
    end

    test "skips .pyc files" do
      assert :skip = FileClassifier.classify("src/main.pyc")
    end

    test "skips lock files" do
      assert :skip = FileClassifier.classify("mix.lock")
      assert :skip = FileClassifier.classify("package-lock.json")
      assert :skip = FileClassifier.classify("yarn.lock")
      assert :skip = FileClassifier.classify("Cargo.lock")
      assert :skip = FileClassifier.classify("poetry.lock")
      assert :skip = FileClassifier.classify("Gemfile.lock")
      assert :skip = FileClassifier.classify("go.sum")
    end

    test "skips minified files" do
      assert :skip = FileClassifier.classify("assets/app.min.js")
      assert :skip = FileClassifier.classify("assets/style.min.css")
    end

    test "skips source map files" do
      assert :skip = FileClassifier.classify("assets/app.js.map")
    end

    test "skips compiled object files" do
      assert :skip = FileClassifier.classify("src/main.o")
      assert :skip = FileClassifier.classify("lib/native.so")
      assert :skip = FileClassifier.classify("lib/native.dylib")
      assert :skip = FileClassifier.classify("src/Main.class")
    end

    test "indexes Elixir source files" do
      assert :index = FileClassifier.classify("lib/familiar/knowledge/entry.ex")
    end

    test "indexes Elixir test files" do
      assert :index = FileClassifier.classify("test/familiar/knowledge_test.exs")
    end

    test "indexes Go source files" do
      assert :index = FileClassifier.classify("handler/song.go")
    end

    test "indexes Python source files" do
      assert :index = FileClassifier.classify("src/main.py")
    end

    test "indexes TypeScript files" do
      assert :index = FileClassifier.classify("src/components/App.tsx")
    end

    test "indexes JavaScript files" do
      assert :index = FileClassifier.classify("src/utils/helper.js")
    end

    test "indexes Ruby files" do
      assert :index = FileClassifier.classify("app/models/user.rb")
    end

    test "indexes Rust files" do
      assert :index = FileClassifier.classify("src/main.rs")
    end

    test "indexes config files" do
      assert :index = FileClassifier.classify("mix.exs")
      assert :index = FileClassifier.classify("package.json")
      assert :index = FileClassifier.classify("Cargo.toml")
      assert :index = FileClassifier.classify("pyproject.toml")
    end

    test "indexes markdown files" do
      assert :index = FileClassifier.classify("README.md")
      assert :index = FileClassifier.classify("docs/guide.md")
    end

    test "indexes YAML and TOML config" do
      assert :index = FileClassifier.classify("config.yaml")
      assert :index = FileClassifier.classify("settings.toml")
    end

    test "skips with custom extra skip patterns" do
      assert :skip = FileClassifier.classify("tmp/cache.txt", skip_dirs: ["tmp/"])
    end

    test "indexes non-matching files as :index by default" do
      assert :index = FileClassifier.classify("Makefile")
    end

    test "does not skip files with names matching skip directory prefixes" do
      # build.txt should not be skipped just because "build/" is a skip dir
      assert :index = FileClassifier.classify("build.txt")
      assert :index = FileClassifier.classify("dist.config")
      assert :index = FileClassifier.classify("target.mk")
    end
  end

  describe "classify/2 with custom indexing config" do
    test "custom source_extensions causes .pdf to index" do
      indexing = %{source_extensions: [".pdf", ".docx"]}
      assert :index = FileClassifier.classify("paper.pdf", indexing: indexing)
      assert :index = FileClassifier.classify("doc.docx", indexing: indexing)
    end

    test "custom skip_dirs skips custom directories" do
      indexing = %{skip_dirs: ["manuscripts/", "drafts/"]}
      assert :skip = FileClassifier.classify("manuscripts/chapter1.md", indexing: indexing)
      assert :skip = FileClassifier.classify("drafts/outline.md", indexing: indexing)
      # Default skip dirs no longer apply when overridden
      assert :index = FileClassifier.classify("node_modules/pkg/index.js", indexing: indexing)
    end

    test "extra skip_dirs merges with indexing config skip_dirs" do
      indexing = %{skip_dirs: [".git/", "vendor/"]}
      opts = [indexing: indexing, skip_dirs: ["extra/"]]
      assert :skip = FileClassifier.classify(".git/config", opts)
      assert :skip = FileClassifier.classify("extra/tmp.txt", opts)
    end

    test "partial config merges with defaults for unspecified keys" do
      # Only override skip_dirs, rest uses defaults
      indexing = %{skip_dirs: ["custom/"]}
      # .beam still skipped (default skip_extensions)
      assert :skip = FileClassifier.classify("lib/mod.beam", indexing: indexing)
      # mix.lock still skipped (default skip_files)
      assert :skip = FileClassifier.classify("mix.lock", indexing: indexing)
      # custom/ now skipped
      assert :skip = FileClassifier.classify("custom/file.txt", indexing: indexing)
    end

    test "empty source_extensions means nothing classified as source" do
      indexing = %{source_extensions: []}
      # .ex files are normally source, but with empty list they're just :index (not skipped)
      assert :index = FileClassifier.classify("lib/app.ex", indexing: indexing)
    end

    test "custom skip_extensions skips custom extensions" do
      indexing = %{skip_extensions: [".log", ".tmp"]}
      assert :skip = FileClassifier.classify("app.log", indexing: indexing)
      assert :skip = FileClassifier.classify("data.tmp", indexing: indexing)
      # Default .beam no longer skipped
      assert :index = FileClassifier.classify("lib/mod.beam", indexing: indexing)
    end

    test "custom skip_files skips custom filenames" do
      indexing = %{skip_files: ["CHANGELOG.md", "LICENSE"]}
      assert :skip = FileClassifier.classify("CHANGELOG.md", indexing: indexing)
      assert :skip = FileClassifier.classify("LICENSE", indexing: indexing)
      # Default mix.lock no longer skipped
      assert :index = FileClassifier.classify("mix.lock", indexing: indexing)
    end
  end

  describe "significance/2 with custom indexing config" do
    test "custom source_extensions changes significance scoring" do
      indexing = %{source_extensions: [".pdf"]}
      assert FileClassifier.significance("paper.pdf", indexing: indexing) == 100
      # .ex no longer scored as source
      assert FileClassifier.significance("lib/app.ex", indexing: indexing) == 10
    end

    test "custom config_files changes significance scoring" do
      indexing = %{config_files: ["Justfile"]}
      assert FileClassifier.significance("Justfile", indexing: indexing) == 80
    end

    test "custom test_patterns changes test detection" do
      indexing = %{test_patterns: ["check/"]}
      assert FileClassifier.significance("check/verify.ex", indexing: indexing) == 50
      # Default test/ no longer detected
      assert FileClassifier.significance("test/app_test.exs", indexing: indexing) == 100
    end
  end

  describe "significance/1" do
    test "source code has highest significance" do
      assert FileClassifier.significance("lib/app.ex") > FileClassifier.significance("README.md")
    end

    test "config files have high significance" do
      assert FileClassifier.significance("mix.exs") > FileClassifier.significance("README.md")
    end

    test "documentation has medium significance" do
      assert FileClassifier.significance("README.md") > 0
    end

    test "test files have medium significance" do
      assert FileClassifier.significance("test/app_test.exs") > 0
    end

    test "unknown files have low significance" do
      assert FileClassifier.significance("random.txt") > 0
    end
  end

  describe "prioritize/2" do
    test "returns all files when under budget" do
      files = ["lib/a.ex", "lib/b.ex", "test/a_test.exs"]
      assert files == FileClassifier.prioritize(files, 200)
    end

    test "truncates to budget, sorted by significance" do
      source = Enum.map(1..5, &"lib/mod#{&1}.ex")
      docs = Enum.map(1..5, &"docs/page#{&1}.md")
      all = docs ++ source

      result = FileClassifier.prioritize(all, 5)
      assert length(result) == 5
      # All source files should be prioritized over docs
      assert Enum.all?(result, &String.starts_with?(&1, "lib/"))
    end

    test "returns deferred count" do
      files = Enum.map(1..10, &"lib/mod#{&1}.ex")
      {kept, deferred_count} = FileClassifier.prioritize_with_info(files, 5)
      assert length(kept) == 5
      assert deferred_count == 5
    end
  end
end
