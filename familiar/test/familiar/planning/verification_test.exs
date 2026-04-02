defmodule Familiar.Planning.VerificationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Familiar.Planning.Verification

  @sample_spec """
  # Add User Accounts

  Generated 2026-04-02 · 3 verified · 1 unverified

  ## Assumptions

  Users table has email and hashed_password columns in db/migrations/001_init.sql
  Auth middleware validates session tokens in lib/auth.ex
  Rate limiting for login attempts exists somewhere
  Config uses `config/runtime.exs` for secrets

  ## Conventions Applied

  Following existing pattern: handler/song.go

  ## Implementation Plan

  Create user schema with proper validation
  """

  @sample_tool_log [
    %{type: "file_read", path: "db/migrations/001_init.sql", timestamp: ~U[2026-04-02 12:00:00Z]},
    %{type: "file_read", path: "lib/auth.ex", timestamp: ~U[2026-04-02 12:00:01Z]},
    %{type: "context_query", path: "knowledge:auth_patterns", timestamp: ~U[2026-04-02 12:00:02Z]}
  ]

  describe "extract_claims/1" do
    test "extracts claims with file references" do
      claims = Verification.extract_claims(@sample_spec)

      file_claim = Enum.find(claims, &(&1.text =~ "001_init.sql"))
      assert file_claim
      assert "db/migrations/001_init.sql" in file_claim.file_refs
    end

    test "extracts backtick-quoted file references" do
      claims = Verification.extract_claims(@sample_spec)

      config_claim = Enum.find(claims, &(&1.text =~ "runtime.exs"))
      assert config_claim
      assert "config/runtime.exs" in config_claim.file_refs
    end

    test "skips headings" do
      claims = Verification.extract_claims(@sample_spec)

      refute Enum.any?(claims, &(&1.text =~ "# Add User"))
      refute Enum.any?(claims, &(&1.text =~ "## Assumptions"))
    end

    test "skips frontmatter lines" do
      claims = Verification.extract_claims(@sample_spec)

      refute Enum.any?(claims, &(&1.text =~ "Generated 2026"))
    end

    test "skips convention annotations" do
      claims = Verification.extract_claims(@sample_spec)

      refute Enum.any?(claims, &(&1.text =~ "Following existing"))
    end

    test "includes claims without file references" do
      claims = Verification.extract_claims(@sample_spec)

      no_ref_claim = Enum.find(claims, &(&1.text =~ "Rate limiting"))
      assert no_ref_claim
      assert no_ref_claim.file_refs == []
    end

    test "returns empty list for empty input" do
      assert [] == Verification.extract_claims("")
    end

    test "handles spec with only headings" do
      assert [] == Verification.extract_claims("# Title\n## Section\n### Sub")
    end
  end

  describe "verify_claims/2" do
    test "marks claims with matching tool calls as verified" do
      claims = [
        %{text: "Users table has email columns", file_refs: ["db/migrations/001_init.sql"]},
        %{text: "Auth middleware validates tokens", file_refs: ["lib/auth.ex"]}
      ]

      results = Verification.verify_claims(claims, @sample_tool_log)

      assert Enum.all?(results, &(&1.status == :verified))
      assert Enum.at(results, 0).source == "db/migrations/001_init.sql"
      assert Enum.at(results, 1).source == "lib/auth.ex"
    end

    test "marks claims without matching tool calls as unverified" do
      claims = [
        %{text: "Rate limiting exists", file_refs: []},
        %{text: "Uses Redis for caching", file_refs: ["lib/cache.ex"]}
      ]

      results = Verification.verify_claims(claims, @sample_tool_log)

      assert Enum.all?(results, &(&1.status == :unverified))
      assert Enum.all?(results, &is_nil(&1.source))
    end

    test "empty tool call log makes all claims unverified" do
      claims = [
        %{text: "Some claim", file_refs: ["lib/auth.ex"]}
      ]

      results = Verification.verify_claims(claims, [])

      assert [%{status: :unverified}] = results
    end

    test "empty claims list returns empty results" do
      assert [] == Verification.verify_claims([], @sample_tool_log)
    end

    test "includes evidence from tool call log" do
      claims = [%{text: "Auth check", file_refs: ["lib/auth.ex"]}]

      [result] = Verification.verify_claims(claims, @sample_tool_log)

      assert result.evidence.path == "lib/auth.ex"
      assert result.evidence.type == "file_read"
    end

    test "claims with multiple file refs are verified if any match" do
      claims = [
        %{text: "DB and cache", file_refs: ["db/migrations/001_init.sql", "lib/cache.ex"]}
      ]

      [result] = Verification.verify_claims(claims, @sample_tool_log)

      assert result.status == :verified
      assert result.source == "db/migrations/001_init.sql"
    end
  end

  describe "annotate_spec/2" do
    test "prepends ✓ to verified claims" do
      results = [
        %{claim: "Users table has email columns in db/migrations/001_init.sql", status: :verified, source: "db/migrations/001_init.sql", evidence: nil}
      ]

      spec = "# Title\n\nUsers table has email columns in db/migrations/001_init.sql"
      annotated = Verification.annotate_spec(spec, results)

      assert annotated =~ "✓ Users table"
      assert annotated =~ "— verified in db/migrations/001_init.sql"
    end

    test "prepends ⚠ to unverified claims" do
      results = [
        %{claim: "Rate limiting exists", status: :unverified, source: nil, evidence: nil}
      ]

      spec = "# Title\n\nRate limiting exists"
      annotated = Verification.annotate_spec(spec, results)

      assert annotated =~ "⚠ Rate limiting"
    end

    test "preserves headings unchanged" do
      results = []
      spec = "# Title\n\n## Section"
      annotated = Verification.annotate_spec(spec, results)

      assert annotated == spec
    end

    test "does not double-annotate already marked lines" do
      results = [
        %{claim: "Auth check in lib/auth.ex", status: :verified, source: "lib/auth.ex", evidence: nil}
      ]

      spec = "✓ Auth check in lib/auth.ex"
      annotated = Verification.annotate_spec(spec, results)

      refute annotated =~ "✓ ✓"
      assert annotated =~ "✓ Auth check"
    end
  end

  describe "build_metadata/2" do
    test "counts verified, unverified, and conventions" do
      results = [
        %{claim: "a", status: :verified, source: "f", evidence: nil},
        %{claim: "b", status: :verified, source: "g", evidence: nil},
        %{claim: "c", status: :unverified, source: nil, evidence: nil}
      ]

      spec = "# Title\n\nFollowing existing pattern: handler/song.go\nFollowing existing pattern: db/repo.go"

      meta = Verification.build_metadata(results, spec)

      assert meta.verified_count == 2
      assert meta.unverified_count == 1
      assert meta.conventions_count == 2
      assert meta.total_claims == 3
    end

    test "returns zeros for empty results" do
      meta = Verification.build_metadata([])

      assert meta.verified_count == 0
      assert meta.unverified_count == 0
      assert meta.conventions_count == 0
      assert meta.total_claims == 0
    end

    test "counts conventions from spec markdown" do
      spec = "Following existing pattern: a\nFollowing existing pattern: b\nFollowing existing pattern: c"
      meta = Verification.build_metadata([], spec)
      assert meta.conventions_count == 3
    end
  end

  describe "property tests" do
    property "every ✓ mark has a corresponding tool call in the log" do
      check all paths <- list_of(file_path_gen(), min_length: 1, max_length: 5) do
        log = Enum.map(paths, &%{type: "file_read", path: &1, timestamp: nil})

        claims =
          Enum.map(paths, fn path ->
            %{text: "Claim about #{path}", file_refs: [path]}
          end)

        results = Verification.verify_claims(claims, log)
        log_paths = MapSet.new(log, & &1.path)

        for result <- results, result.status == :verified do
          assert MapSet.member?(log_paths, result.source),
                 "Verified claim source #{result.source} not in tool call log"
        end
      end
    end

    property "empty tool call log makes all claims unverified" do
      check all paths <- list_of(file_path_gen(), min_length: 1, max_length: 5) do
        claims =
          Enum.map(paths, fn path ->
            %{text: "Claim about #{path}", file_refs: [path]}
          end)

        results = Verification.verify_claims(claims, [])

        assert Enum.all?(results, &(&1.status == :unverified)),
               "Expected all claims unverified with empty log"
      end
    end

    property "claims with no file_refs are always unverified" do
      check all texts <- list_of(string(:alphanumeric, min_length: 3), min_length: 1, max_length: 5),
                log <- list_of(tool_call_gen(), max_length: 5) do
        claims = Enum.map(texts, &%{text: &1, file_refs: []})

        results = Verification.verify_claims(claims, log)

        assert Enum.all?(results, &(&1.status == :unverified)),
               "Claims with no file refs should always be unverified"
      end
    end

    property "build_metadata counts match actual results" do
      check all n_verified <- integer(0..10),
                n_unverified <- integer(0..10) do
        verified_list =
          if n_verified > 0,
            do: Enum.map(1..n_verified, &%{claim: "v#{&1}", status: :verified, source: "f", evidence: nil}),
            else: []

        unverified_list =
          if n_unverified > 0,
            do: Enum.map(1..n_unverified, &%{claim: "u#{&1}", status: :unverified, source: nil, evidence: nil}),
            else: []

        results = verified_list ++ unverified_list

        meta = Verification.build_metadata(results)

        assert meta.verified_count == n_verified
        assert meta.unverified_count == n_unverified
        assert meta.total_claims == n_verified + n_unverified
      end
    end

    property "every file_read tool call referenced by a claim appears in verified results" do
      check all paths <- list_of(file_path_gen(), min_length: 1, max_length: 5) do
        log = Enum.map(paths, &%{type: "file_read", path: &1, timestamp: nil})

        claims =
          Enum.map(paths, fn path ->
            %{text: "Claim referencing #{path}", file_refs: [path]}
          end)

        results = Verification.verify_claims(claims, log)

        # Every claim that has a matching tool call must be verified
        for {claim, result} <- Enum.zip(claims, results) do
          if Enum.any?(log, &(&1.path == hd(claim.file_refs))) do
            assert result.status == :verified,
                   "Claim for #{hd(claim.file_refs)} should be verified but was #{result.status}"
          end
        end
      end
    end

    defp file_path_gen do
      gen all dir <- member_of(["lib", "db", "config", "test"]),
              name <- string(:alphanumeric, min_length: 2, max_length: 10),
              ext <- member_of(["ex", "exs", "sql", "json"]) do
        "#{dir}/#{name}.#{ext}"
      end
    end

    defp tool_call_gen do
      gen all path <- file_path_gen(),
              type <- member_of(["file_read", "context_query"]) do
        %{type: type, path: path, timestamp: nil}
      end
    end
  end
end
