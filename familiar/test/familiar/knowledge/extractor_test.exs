defmodule Familiar.Knowledge.ExtractorTest do
  use ExUnit.Case, async: false
  use Familiar.MockCase

  alias Familiar.Knowledge.Entry
  alias Familiar.Knowledge.Extractor

  describe "extract_from_file/1" do
    test "calls LLM and parses valid JSON response" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 "type" => "file_summary",
                 "text" => "GenServer managing daemon lifecycle",
                 "source_file" => "lib/server.ex"
               },
               %{
                 "type" => "convention",
                 "text" => "Uses tagged error tuples {:error, {type, details}}",
                 "source_file" => "lib/server.ex"
               }
             ])
         }}
      end)

      file = %{relative_path: "lib/server.ex", content: "defmodule Server do end"}
      entries = Extractor.extract_from_file(file)

      assert length(entries) == 2
      assert Enum.at(entries, 0).type == "file_summary"
      assert Enum.at(entries, 0).source == "init_scan"
      assert Enum.at(entries, 1).type == "convention"
    end

    test "returns empty list on LLM error" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:error, {:provider_unavailable, %{reason: :timeout}}}
      end)

      file = %{relative_path: "lib/app.ex", content: "defmodule App do end"}
      assert [] == Extractor.extract_from_file(file)
    end

    test "returns empty list on invalid JSON response" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok, %{content: "This is not JSON"}}
      end)

      file = %{relative_path: "lib/app.ex", content: "defmodule App do end"}
      assert [] == Extractor.extract_from_file(file)
    end

    test "filters out entries with invalid type format or empty text" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{"type" => "file_summary", "text" => "Valid entry", "source_file" => "lib/a.ex"},
               %{"type" => "Has Spaces", "text" => "Bad type", "source_file" => "lib/a.ex"},
               %{"type" => "convention", "text" => "", "source_file" => "lib/a.ex"}
             ])
         }}
      end)

      file = %{relative_path: "lib/a.ex", content: "code"}
      entries = Extractor.extract_from_file(file)
      assert length(entries) == 1
      assert hd(entries).type == "file_summary"
    end

    test "accepts custom snake_case types from LLM" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{
                 "type" => "experiment",
                 "text" => "Custom type entry",
                 "source_file" => "lib/a.ex"
               }
             ])
         }}
      end)

      file = %{relative_path: "lib/a.ex", content: "code"}
      entries = Extractor.extract_from_file(file)
      assert length(entries) == 1
      assert hd(entries).type == "experiment"
    end

    test "uses default source_file when entry omits it" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{"type" => "file_summary", "text" => "A module"}
             ])
         }}
      end)

      file = %{relative_path: "lib/app.ex", content: "code"}
      [entry] = Extractor.extract_from_file(file)
      assert entry.source_file == "lib/app.ex"
    end
  end

  describe "extract_from_files/1" do
    test "extracts from multiple files" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, 2, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{"type" => "file_summary", "text" => "A module", "source_file" => "lib/a.ex"}
             ])
         }}
      end)

      files = [
        %{relative_path: "lib/a.ex", content: "code a"},
        %{relative_path: "lib/b.ex", content: "code b"}
      ]

      entries = Extractor.extract_from_files(files)
      assert length(entries) == 2
    end
  end

  describe "build_prompt/2" do
    test "includes file path and content" do
      prompt = Extractor.build_prompt("lib/app.ex", "defmodule App do end")
      assert prompt =~ "lib/app.ex"
      assert prompt =~ "defmodule App do end"
    end

    test "includes default types from Entry.default_types/0" do
      prompt = Extractor.build_prompt("lib/app.ex", "code")

      for type <- Entry.default_types() do
        assert prompt =~ ~s("#{type}"), "Expected prompt to include type #{type}"
      end
    end

    test "truncates very long content" do
      long_content = String.duplicate("x", 5000)
      prompt = Extractor.build_prompt("lib/big.ex", long_content)
      # Prompt should contain truncated content (4000 chars max)
      assert String.length(prompt) < 5000 + 500
    end

    test "uses custom template from .familiar/system/extractor.md when present" do
      # Set up a temp project dir with a custom template
      tmp_dir =
        System.tmp_dir!() |> Path.join("extractor_tpl_#{System.unique_integer([:positive])}")

      system_dir = Path.join(tmp_dir, ".familiar/system")
      File.mkdir_p!(system_dir)

      custom_template =
        "CUSTOM PROMPT for {{file_path}}\nTypes: {{valid_types}}\n```\n{{content}}\n```"

      File.write!(Path.join(system_dir, "extractor.md"), custom_template)

      original_project_dir = Application.get_env(:familiar, :project_dir)
      Application.put_env(:familiar, :project_dir, tmp_dir)

      try do
        prompt = Extractor.build_prompt("lib/my.ex", "hello world")
        assert prompt =~ "CUSTOM PROMPT for lib/my.ex"
        assert prompt =~ "hello world"
        refute prompt =~ "{{file_path}}"
        refute prompt =~ "{{content}}"
        refute prompt =~ "{{valid_types}}"
      after
        Application.put_env(:familiar, :project_dir, original_project_dir)
        File.rm_rf!(tmp_dir)
      end
    end

    test "falls back to default template when custom file is absent" do
      # Point to a temp dir with no .familiar/system/extractor.md
      tmp_dir =
        System.tmp_dir!() |> Path.join("extractor_fb_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      original_project_dir = Application.get_env(:familiar, :project_dir)
      Application.put_env(:familiar, :project_dir, tmp_dir)

      try do
        prompt = Extractor.build_prompt("lib/app.ex", "code")
        # Should still produce a valid prompt with the default template content
        assert prompt =~ "lib/app.ex"
        assert prompt =~ "JSON array"
        assert prompt =~ "code"
      after
        Application.put_env(:familiar, :project_dir, original_project_dir)
        File.rm_rf!(tmp_dir)
      end
    end

    test "interpolates all template variables" do
      prompt = Extractor.build_prompt("lib/demo.ex", "some content here")

      # {{file_path}} interpolated
      assert prompt =~ "lib/demo.ex"
      # {{content}} interpolated
      assert prompt =~ "some content here"
      # {{valid_types}} interpolated — should contain quoted type names
      for type <- Entry.default_types() do
        assert prompt =~ ~s("#{type}")
      end

      # No raw template variables remain
      refute prompt =~ "{{file_path}}"
      refute prompt =~ "{{content}}"
      refute prompt =~ "{{valid_types}}"
    end
  end

  describe "parse_extraction_response/2" do
    test "parses valid JSON array" do
      json =
        Jason.encode!([
          %{"type" => "file_summary", "text" => "A server module", "source_file" => "lib/s.ex"}
        ])

      entries = Extractor.parse_extraction_response(json, "lib/s.ex")
      assert length(entries) == 1
      assert hd(entries).text == "A server module"
      assert hd(entries).source == "init_scan"
    end

    test "strips secrets from entry text" do
      json =
        Jason.encode!([
          %{
            "type" => "decision",
            "text" => "Uses Stripe key sk_live_abcdefghijklmnopqrstuvwxyz for payments",
            "source_file" => "lib/pay.ex"
          }
        ])

      [entry] = Extractor.parse_extraction_response(json, "lib/pay.ex")
      refute entry.text =~ "sk_live_"
      assert entry.text =~ "[STRIPE_SECRET_KEY]"
    end

    test "returns empty list for non-array JSON" do
      non_array = ~s({"key": "value"})
      assert [] == Extractor.parse_extraction_response(non_array, "lib/a.ex")
    end

    test "returns empty list for invalid JSON" do
      assert [] == Extractor.parse_extraction_response("not json", "lib/a.ex")
    end
  end
end
