defmodule Familiar.Knowledge.EntryTest do
  use Familiar.DataCase, async: true

  alias Familiar.Knowledge.Entry

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{text: "some knowledge", type: "convention", source: "init_scan"}
      changeset = Entry.changeset(%Entry{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      attrs = %{
        text: "Handler files follow snake_case",
        type: "convention",
        source: "init_scan",
        source_file: "handler/song.go",
        metadata: ~s|{"evidence_count": 5}|
      }

      changeset = Entry.changeset(%Entry{}, attrs)
      assert changeset.valid?
    end

    test "invalid without text" do
      changeset = Entry.changeset(%Entry{}, %{type: "convention", source: "init_scan"})
      refute changeset.valid?
      assert %{text: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without type" do
      changeset = Entry.changeset(%Entry{}, %{text: "some text", source: "init_scan"})
      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without source" do
      changeset = Entry.changeset(%Entry{}, %{text: "some text", type: "convention"})
      refute changeset.valid?
      assert %{source: ["can't be blank"]} = errors_on(changeset)
    end

    test "accepts all default types" do
      for type <- Entry.default_types() do
        changeset = Entry.changeset(%Entry{}, %{text: "t", type: type, source: "init_scan"})
        assert changeset.valid?, "Expected type #{type} to be valid"
      end
    end

    test "accepts all default sources" do
      for source <- Entry.default_sources() do
        changeset = Entry.changeset(%Entry{}, %{text: "t", type: "convention", source: source})
        assert changeset.valid?, "Expected source #{source} to be valid"
      end
    end

    test "accepts custom type — experiment" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "experiment", source: "init_scan"})
      assert changeset.valid?
    end

    test "accepts custom type — runbook" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "runbook", source: "init_scan"})
      assert changeset.valid?
    end

    test "accepts custom source — webhook" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "convention", source: "webhook"})
      assert changeset.valid?
    end

    test "accepts valid snake_case type" do
      changeset =
        Entry.changeset(%Entry{}, %{
          text: "t",
          type: "valid_snake_case_type",
          source: "init_scan"
        })

      assert changeset.valid?
    end

    test "rejects empty type" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "", source: "init_scan"})
      refute changeset.valid?
      assert %{type: [_]} = errors_on(changeset)
    end

    test "rejects type with spaces" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "Has Spaces", source: "init_scan"})
      refute changeset.valid?
      assert %{type: [_]} = errors_on(changeset)
    end

    test "rejects type starting with digit" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "123start", source: "init_scan"})
      refute changeset.valid?
      assert %{type: [_]} = errors_on(changeset)
    end

    test "rejects type longer than 50 characters" do
      long_type = String.duplicate("a", 51)

      changeset =
        Entry.changeset(%Entry{}, %{text: "t", type: long_type, source: "init_scan"})

      refute changeset.valid?
      assert %{type: [_]} = errors_on(changeset)
    end

    test "rejects empty source" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "convention", source: ""})
      refute changeset.valid?
      assert %{source: [_]} = errors_on(changeset)
    end

    test "rejects source with uppercase" do
      changeset = Entry.changeset(%Entry{}, %{text: "t", type: "convention", source: "InitScan"})
      refute changeset.valid?
      assert %{source: [_]} = errors_on(changeset)
    end

    test "accepts checked_at timestamp" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Entry.changeset(%Entry{}, %{
          text: "some knowledge",
          type: "convention",
          source: "init_scan",
          checked_at: now
        })

      assert changeset.valid?
      assert get_change(changeset, :checked_at) == now
    end

    test "valid without checked_at" do
      changeset =
        Entry.changeset(%Entry{}, %{
          text: "some knowledge",
          type: "convention",
          source: "init_scan"
        })

      assert changeset.valid?
      assert get_change(changeset, :checked_at) == nil
    end
  end

  describe "default_types/0 and default_sources/0" do
    test "default_types returns a list of strings" do
      types = Entry.default_types()
      assert is_list(types)
      assert Enum.all?(types, &is_binary/1)
      assert "convention" in types
      assert "file_summary" in types
    end

    test "default_sources returns a list of strings" do
      sources = Entry.default_sources()
      assert is_list(sources)
      assert Enum.all?(sources, &is_binary/1)
      assert "init_scan" in sources
      assert "post_task" in sources
    end
  end
end
