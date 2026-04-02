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

    test "invalid with unknown type" do
      attrs = %{text: "text", type: "unknown", source: "init_scan"}
      changeset = Entry.changeset(%Entry{}, attrs)
      refute changeset.valid?
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "invalid with unknown source" do
      attrs = %{text: "text", type: "convention", source: "unknown"}
      changeset = Entry.changeset(%Entry{}, attrs)
      refute changeset.valid?
      assert %{source: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts all valid types" do
      for type <- Entry.valid_types() do
        changeset = Entry.changeset(%Entry{}, %{text: "t", type: type, source: "init_scan"})
        assert changeset.valid?, "Expected type #{type} to be valid"
      end
    end

    test "accepts all valid sources" do
      for source <- Entry.valid_sources() do
        changeset = Entry.changeset(%Entry{}, %{text: "t", type: "convention", source: source})
        assert changeset.valid?, "Expected source #{source} to be valid"
      end
    end
  end
end
