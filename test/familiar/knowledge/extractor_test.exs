defmodule Familiar.Knowledge.ExtractorTest do
  use ExUnit.Case, async: false
  use Familiar.MockCase

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

    test "filters out entries with invalid types" do
      Mox.expect(Familiar.Providers.LLMMock, :chat, fn _messages, _opts ->
        {:ok,
         %{
           content:
             Jason.encode!([
               %{"type" => "file_summary", "text" => "Valid entry", "source_file" => "lib/a.ex"},
               %{"type" => "invalid_type", "text" => "Bad entry", "source_file" => "lib/a.ex"},
               %{"type" => "convention", "text" => "", "source_file" => "lib/a.ex"}
             ])
         }}
      end)

      file = %{relative_path: "lib/a.ex", content: "code"}
      entries = Extractor.extract_from_file(file)
      assert length(entries) == 1
      assert hd(entries).type == "file_summary"
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

    test "truncates very long content" do
      long_content = String.duplicate("x", 5000)
      prompt = Extractor.build_prompt("lib/big.ex", long_content)
      # Prompt should contain truncated content (4000 chars max)
      assert String.length(prompt) < 5000 + 500
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
