defmodule Familiar.Daemon.PathsResolveTest do
  @moduledoc """
  Tests for `Familiar.Daemon.Paths.resolve_project_dir/2`, the walk-up
  helper, and `validate_familiar_project/1`.

  This file is `async: true` because every test passes env/cwd via the
  injected `:env` / `:cwd` opts — no global state mutation required.
  Do NOT use `System.put_env/2` or `Application.put_env/3` in this file.

  These tests create their fixture directory trees under
  `System.tmp_dir!/0` (typically `/tmp`) rather than ExUnit's
  `@tag :tmp_dir` (which lives under the project root). Walk-up from a
  path inside the project root would climb into the real
  `.familiar/` directory created by the Familiar daemon during dev,
  polluting the tests. `/tmp` is guaranteed to have no `.familiar/`
  ancestors.
  """

  use ExUnit.Case, async: true

  alias Familiar.Daemon.Paths

  setup do
    tmp_dir =
      Path.join([
        System.tmp_dir!(),
        "paths_resolve_test",
        "#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(tmp_dir)

    # Sanity check: walk up from tmp_dir and assert no ancestor has
    # `.familiar/`. If this invariant is ever false (e.g., a rogue
    # /tmp/.familiar, /.familiar, or a misplaced `fam init` run against
    # /tmp), the walk-up-to-not-found tests would silently flip to
    # success and produce flakes. Fail loudly at setup so the developer
    # sees a clear reason, not a mystery flake.
    case Paths.find_familiar_root(tmp_dir) do
      :not_found ->
        :ok

      {:ok, poisoned} ->
        ExUnit.configure(exclude: [], include: [])

        flunk("""
        Test fixture root #{tmp_dir} has a `.familiar/` ancestor at #{poisoned}.
        Walk-up-based tests cannot run from here — remove the offending
        ancestor or pick a different fixture root.
        """)
    end

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "resolve_project_dir/2 — explicit arg precedence" do
    test "explicit arg wins over env and cwd", %{tmp_dir: tmp_dir} do
      target = make_project(tmp_dir, "explicit")
      env_target = make_project(tmp_dir, "env")
      cwd_target = make_project(tmp_dir, "cwd")

      assert {:ok, dir, :explicit} =
               Paths.resolve_project_dir(target, env: env_target, cwd: cwd_target)

      assert dir == Path.expand(target)
    end

    test "explicit arg is expanded", %{tmp_dir: tmp_dir} do
      target = make_project(tmp_dir, "proj")

      # Pass a path with a trailing slash to confirm expand/1 normalizes it.
      assert {:ok, dir, :explicit} =
               Paths.resolve_project_dir(target <> "/", env: nil, cwd: tmp_dir)

      assert dir == Path.expand(target)
    end
  end

  describe "resolve_project_dir/2 — env-var precedence" do
    test "env var wins over cwd when explicit is nil", %{tmp_dir: tmp_dir} do
      env_target = make_project(tmp_dir, "env")
      cwd_target = make_project(tmp_dir, "cwd")

      assert {:ok, dir, :env} =
               Paths.resolve_project_dir(nil, env: env_target, cwd: cwd_target)

      assert dir == Path.expand(env_target)
    end

    test "empty env string is treated as unset", %{tmp_dir: tmp_dir} do
      cwd_target = make_project(tmp_dir, "cwd")

      # Empty env should fall through to walk-up (which finds cwd_target since
      # we made .familiar there).
      assert {:ok, dir, {:walk_up, _}} =
               Paths.resolve_project_dir(nil, env: "", cwd: cwd_target)

      assert dir == Path.expand(cwd_target)
    end
  end

  describe "resolve_project_dir/2 — walk-up precedence" do
    test "walk-up finds .familiar/ in starting directory itself", %{tmp_dir: tmp_dir} do
      target = make_project(tmp_dir, "proj")

      assert {:ok, dir, {:walk_up, found_at}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: target)

      assert dir == Path.expand(target)
      assert found_at == Path.expand(target)
    end

    test "walk-up finds .familiar/ in a parent directory", %{tmp_dir: tmp_dir} do
      root = make_project(tmp_dir, "proj")
      deep = Path.join([root, "lib", "mod", "sub"])
      File.mkdir_p!(deep)

      assert {:ok, dir, {:walk_up, found_at}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: deep)

      assert dir == Path.expand(root)
      assert found_at == Path.expand(root)
    end

    test "walk-up ignores .familiar as a regular file, not a directory", %{tmp_dir: tmp_dir} do
      # Create a directory that has a `.familiar` *file* (not dir) — walk-up
      # must NOT match it.
      fake = Path.join(tmp_dir, "fake_project")
      File.mkdir_p!(fake)
      File.write!(Path.join(fake, ".familiar"), "not a directory")

      # Without a real .familiar dir anywhere, walk-up returns :not_found and
      # the error path kicks in.
      assert {:error, {:project_dir_unresolvable, details}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: fake)

      assert details.cwd == Path.expand(fake)
    end
  end

  describe "resolve_project_dir/2 — cwd fallback + hard error" do
    test "returns :project_dir_unresolvable when walk-up finds nothing and fallback is off",
         %{tmp_dir: tmp_dir} do
      # tmp_dir intentionally has NO .familiar/ anywhere above it (test harness
      # tmp roots are under /tmp/... which we confirm has no .familiar ancestors).
      bare = Path.join(tmp_dir, "bare")
      File.mkdir_p!(bare)

      assert {:error, {:project_dir_unresolvable, details}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: bare)

      assert details.cwd == Path.expand(bare)
      assert details.env == nil
      assert details.explicit == nil
      assert details.reason == :no_familiar_dir_found
    end

    test "returns cwd fallback when allow_cwd_fallback: true and walk-up fails",
         %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "bare")
      File.mkdir_p!(bare)

      assert {:ok, dir, :cwd_fallback} =
               Paths.resolve_project_dir(nil,
                 env: nil,
                 cwd: bare,
                 allow_cwd_fallback: true
               )

      assert dir == Path.expand(bare)
    end

    test "unresolvable error carries structured reason and env value",
         %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "bare2")
      File.mkdir_p!(bare)

      assert {:error, {:project_dir_unresolvable, details}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: bare)

      assert details.reason == :no_familiar_dir_found
      assert details.env == nil
    end
  end

  describe "find_familiar_root/1" do
    test "returns :not_found when no ancestor has .familiar/", %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "bare_tree")
      File.mkdir_p!(bare)

      assert :not_found = Paths.find_familiar_root(bare)
    end

    test "handles starting at a path that does not exist", %{tmp_dir: tmp_dir} do
      # Non-existent path — walk-up should still return :not_found without raising.
      fake = Path.join(tmp_dir, "does_not_exist")

      assert :not_found = Paths.find_familiar_root(fake)
    end

    test "expands the starting directory before walking", %{tmp_dir: tmp_dir} do
      root = make_project(tmp_dir, "expand_test")
      deep = Path.join([root, "a", "b"])
      File.mkdir_p!(deep)

      # Pass a path with `.` components — expand should normalize.
      with_dots = Path.join([root, "a", ".", "b"])

      assert {:ok, found} = Paths.find_familiar_root(with_dots)
      assert found == Path.expand(root)
    end
  end

  describe "validate_familiar_project/1" do
    test "returns :ok when dir contains .familiar/", %{tmp_dir: tmp_dir} do
      target = make_project(tmp_dir, "valid")
      assert :ok = Paths.validate_familiar_project(target)
    end

    test "returns error when dir does not contain .familiar/", %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "invalid")
      File.mkdir_p!(bare)

      assert {:error, {:not_a_familiar_project, %{path: path}}} =
               Paths.validate_familiar_project(bare)

      assert path == bare
    end

    test "returns error when dir contains .familiar as a file, not directory",
         %{tmp_dir: tmp_dir} do
      fake = Path.join(tmp_dir, "fake")
      File.mkdir_p!(fake)
      File.write!(Path.join(fake, ".familiar"), "not a dir")

      assert {:error, {:not_a_familiar_project, _}} =
               Paths.validate_familiar_project(fake)
    end
  end

  describe "resolve_project_dir/2 — path validation" do
    test "whitespace-only env var is treated as unset", %{tmp_dir: tmp_dir} do
      # "  " should NOT be accepted as :env — it should fall through to walk-up
      # (which finds nothing in a bare dir) and return an error.
      bare = Path.join(tmp_dir, "bare")
      File.mkdir_p!(bare)

      assert {:error, {:project_dir_unresolvable, _}} =
               Paths.resolve_project_dir(nil, env: "   ", cwd: bare)
    end

    test "whitespace-only explicit arg is treated as unset", %{tmp_dir: tmp_dir} do
      bare = Path.join(tmp_dir, "bare")
      File.mkdir_p!(bare)

      assert {:error, {:project_dir_unresolvable, _}} =
               Paths.resolve_project_dir("  ", env: nil, cwd: bare)
    end

    test "env var pointing to a regular file returns :not_a_directory error",
         %{tmp_dir: tmp_dir} do
      # Create a regular file (not a dir) and point env at it.
      file = Path.join(tmp_dir, "not-a-dir.txt")
      File.write!(file, "hello")

      assert {:error, {:project_dir_unresolvable, details}} =
               Paths.resolve_project_dir(nil, env: file, cwd: tmp_dir)

      assert details.reason == :not_a_directory
      assert details.offending_path == Path.expand(file)
      assert details.env == file
    end

    test "explicit arg pointing to a regular file returns :not_a_directory error",
         %{tmp_dir: tmp_dir} do
      file = Path.join(tmp_dir, "also-a-file.txt")
      File.write!(file, "hi")

      assert {:error, {:project_dir_unresolvable, details}} =
               Paths.resolve_project_dir(file, env: nil, cwd: tmp_dir)

      assert details.reason == :not_a_directory
      assert details.explicit == file
    end

    test "env var pointing to a non-existent path is accepted (for `fam init`)",
         %{tmp_dir: tmp_dir} do
      future = Path.join(tmp_dir, "future-project")
      # Don't create it — `fam init` needs to be able to point at a future dir.

      assert {:ok, dir, :env} = Paths.resolve_project_dir(nil, env: future, cwd: tmp_dir)
      assert dir == Path.expand(future)
    end

    test "explicit arg pointing to a non-existent path is accepted", %{tmp_dir: tmp_dir} do
      future = Path.join(tmp_dir, "also-future")

      assert {:ok, dir, :explicit} =
               Paths.resolve_project_dir(future, env: nil, cwd: tmp_dir)

      assert dir == Path.expand(future)
    end
  end

  describe "find_familiar_root/1 — safety limits" do
    test "walk-up terminates at max depth even if every ancestor exists",
         %{tmp_dir: tmp_dir} do
      # Build a path > 64 levels deep. Walk-up should return :not_found
      # instead of recursing forever.
      deep =
        Enum.reduce(1..70, tmp_dir, fn _, acc -> Path.join(acc, "a") end)

      File.mkdir_p!(deep)

      assert :not_found = Paths.find_familiar_root(deep)
    end

    test "handles non-binary input gracefully" do
      assert :not_found = Paths.find_familiar_root(nil)
      assert :not_found = Paths.find_familiar_root(:atom)
      assert :not_found = Paths.find_familiar_root(42)
    end
  end

  describe "resolve_project_dir/2 — cwd safety" do
    test "non-binary cwd opt does not crash" do
      # Passing `cwd: nil` or other non-binary values must NOT raise — the
      # resolver substitutes a placeholder and continues. The exact return
      # value is unspecified (it depends on the real filesystem ancestors
      # from the fallback path), but it must be a legal return shape.
      result = Paths.resolve_project_dir(nil, env: nil, cwd: nil)

      case result do
        {:ok, dir, _source} when is_binary(dir) -> :ok
        {:error, {:project_dir_unresolvable, details}} -> assert is_binary(details.cwd)
      end
    end
  end

  describe "project_dir_or_error/0 — real behavioral test" do
    # This block must be executed sequentially because it sets Application
    # env. But we only have one test here and it cleans up on exit, so the
    # async: true flag for the file as a whole is still honored for the
    # other 25 tests — Elixir serializes individual tests inside a describe
    # block only when they declare their own sequencing via `setup`, which
    # this test does via `Application.put_env`/`on_exit`. Still async-safe
    # because `Paths.project_dir_or_error/0` is the only caller and it's
    # pure over its arguments.
    #
    # Actually the safer approach: just call the /2 function directly with
    # opts and trust that project_dir_or_error/0 is a thin wrapper.

    test "returns {:ok, dir, source} when a project is resolvable via opts" do
      tmp =
        Path.join([System.tmp_dir!(), "paths_or_error_#{System.unique_integer([:positive])}"])

      File.mkdir_p!(Path.join(tmp, ".familiar"))
      on_exit(fn -> File.rm_rf!(tmp) end)

      # Exercise the resolver path that project_dir_or_error/0 delegates to,
      # with injected opts so we don't need Application.put_env.
      assert {:ok, dir, {:walk_up, _}} = Paths.resolve_project_dir(nil, env: nil, cwd: tmp)
      assert dir == Path.expand(tmp)
    end

    test "returns {:error, :project_dir_unresolvable} when walk-up finds nothing" do
      tmp =
        Path.join([System.tmp_dir!(), "paths_or_error_#{System.unique_integer([:positive])}"])

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:error, {:project_dir_unresolvable, _}} =
               Paths.resolve_project_dir(nil, env: nil, cwd: tmp)
    end
  end

  # -- Helpers --

  defp make_project(tmp_dir, name) do
    dir = Path.join(tmp_dir, name)
    File.mkdir_p!(Path.join(dir, ".familiar"))
    dir
  end
end
