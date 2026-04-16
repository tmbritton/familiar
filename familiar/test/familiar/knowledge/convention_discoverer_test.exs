defmodule Familiar.Knowledge.ConventionDiscovererTest do
  use Familiar.DataCase, async: false
  use Familiar.MockCase

  alias Familiar.Knowledge.ConventionDiscoverer

  describe "discover_structural/1" do
    test "detects file naming patterns" do
      files = [
        %{relative_path: "lib/my_app.ex", content: ""},
        %{relative_path: "lib/my_app/server.ex", content: ""},
        %{relative_path: "lib/my_app/worker.ex", content: ""},
        %{relative_path: "lib/MyModule.ex", content: ""}
      ]

      conventions = ConventionDiscoverer.discover_structural(files)

      naming = Enum.find(conventions, &(&1.type == "convention" and &1.text =~ "snake_case"))
      assert naming
      meta = Jason.decode!(naming.metadata)
      assert meta["evidence_count"] == 3
      assert meta["evidence_total"] == 4
    end

    test "detects directory structure patterns" do
      files = [
        %{relative_path: "lib/app.ex", content: ""},
        %{relative_path: "lib/app/server.ex", content: ""},
        %{relative_path: "test/app_test.exs", content: ""},
        %{relative_path: "test/app/server_test.exs", content: ""}
      ]

      conventions = ConventionDiscoverer.discover_structural(files)

      test_mirror =
        Enum.find(conventions, &(&1.type == "convention" and &1.text =~ "test"))

      assert test_mirror
    end

    test "detects file extension distribution" do
      files =
        Enum.map(1..10, &%{relative_path: "lib/mod#{&1}.ex", content: ""}) ++
          [%{relative_path: "lib/helper.exs", content: ""}]

      conventions = ConventionDiscoverer.discover_structural(files)

      ext = Enum.find(conventions, &(&1.type == "convention" and &1.text =~ ".ex"))
      assert ext
    end

    test "returns empty list for empty file list" do
      assert [] == ConventionDiscoverer.discover_structural([])
    end
  end

  describe "discover_with_llm/1" do
    test "calls LLM for cross-cutting convention analysis" do
      files = [
        %{relative_path: "lib/app.ex", content: "defmodule App do end"},
        %{relative_path: "lib/server.ex", content: "defmodule Server do end"}
      ]

      Mox.expect(Familiar.Providers.LLMMock, :chat, fn messages, _opts ->
        prompt = hd(messages).content
        assert prompt =~ "conventions"

        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 "type" => "convention",
                 "text" => "All modules use single-level nesting under App namespace",
                 "evidence_count" => 2,
                 "evidence_total" => 2
               }
             ])
         }}
      end)

      conventions = ConventionDiscoverer.discover_with_llm(files)
      assert length(conventions) == 1
      assert hd(conventions).source == "init_scan"

      meta = Jason.decode!(hd(conventions).metadata)
      assert meta["evidence_count"] == 2
    end

    test "returns empty list on LLM error" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{}}}
      end)

      assert [] == ConventionDiscoverer.discover_with_llm([%{relative_path: "a.ex", content: ""}])
    end
  end

  describe "discover/2" do
    test "combines structural and LLM conventions" do
      files = [
        %{relative_path: "lib/my_app.ex", content: "defmodule MyApp do end"},
        %{relative_path: "lib/my_app/server.ex", content: "defmodule MyApp.Server do end"},
        %{relative_path: "mix.exs", content: "defmodule MyApp.MixProject do end"}
      ]

      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 "type" => "convention",
                 "text" => "Error handling uses tagged tuples {:error, {type, details}}",
                 "evidence_count" => 3,
                 "evidence_total" => 3
               }
             ])
         }}
      end)

      conventions = ConventionDiscoverer.discover(files)

      # Should have both structural and LLM conventions
      assert length(conventions) >= 2
      assert Enum.all?(conventions, &(&1.type == "convention"))
      assert Enum.all?(conventions, &(&1.source == "init_scan"))
    end
  end
end
