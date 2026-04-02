defmodule Familiar.Knowledge.ConventionReviewer do
  @moduledoc """
  Interactive convention review flow.

  Presents discovered conventions to the user and allows them to
  accept all, accept individually, edit, or reject conventions.
  """

  alias Familiar.Knowledge.Entry
  alias Familiar.Repo

  @doc """
  Run an interactive review of conventions.

  Options:
  - `:puts_fn` — function for output `(String.t() -> :ok)` (default: IO.puts(:stderr, ...))
  - `:gets_fn` — function for input `(String.t() -> String.t())` (default: IO.gets/1)

  Returns `{:ok, %{accepted: N, rejected: N, edited: N}}`.
  """
  @spec review([map()], keyword()) :: {:ok, map()}
  def review(conventions, opts \\ []) do
    puts_fn = Keyword.get(opts, :puts_fn, &default_puts/1)
    gets_fn = Keyword.get(opts, :gets_fn, &IO.gets/1)

    if conventions == [] do
      {:ok, %{accepted: 0, rejected: 0, edited: 0}}
    else
      puts_fn.("\nDiscovered #{length(conventions)} conventions:\n")
      display_conventions(conventions, puts_fn)

      puts_fn.("\nOptions:")
      puts_fn.("  [a] Accept all conventions")
      puts_fn.("  [r] Review individually")
      puts_fn.("  [s] Skip review (accept all without marking as reviewed)")

      choice = gets_fn.("Choice: ") |> to_string() |> String.trim() |> String.downcase()

      case choice do
        "a" -> accept_all(conventions)
        "r" -> review_individually(conventions, puts_fn, gets_fn)
        _ -> {:ok, %{accepted: length(conventions), rejected: 0, edited: 0}}
      end
    end
  end

  # -- Private --

  defp default_puts(msg), do: IO.puts(:stderr, msg)

  defp display_conventions(conventions, puts_fn) do
    conventions
    |> Enum.with_index(1)
    |> Enum.each(fn {conv, idx} ->
      evidence = "(#{conv.evidence_count}/#{conv.evidence_total})"
      puts_fn.("  #{idx}. #{conv.text} #{evidence}")
    end)
  end

  defp accept_all(conventions) do
    Enum.each(conventions, &mark_reviewed(&1.id))
    {:ok, %{accepted: length(conventions), rejected: 0, edited: 0}}
  end

  defp review_individually(conventions, puts_fn, gets_fn) do
    results = Enum.map(conventions, &review_single(&1, puts_fn, gets_fn))

    {:ok,
     %{
       accepted: Enum.count(results, &(&1 == :accepted)),
       rejected: Enum.count(results, &(&1 == :rejected)),
       edited: Enum.count(results, &(&1 == :edited))
     }}
  end

  defp review_single(conv, puts_fn, gets_fn) do
    evidence = "(#{conv.evidence_count}/#{conv.evidence_total})"
    puts_fn.("\n  #{conv.text} #{evidence}")
    puts_fn.("  [a] Accept  [e] Edit  [r] Reject  [s] Skip")

    choice = gets_fn.("  > ") |> to_string() |> String.trim() |> String.downcase()
    apply_review_choice(choice, conv, gets_fn)
  end

  defp apply_review_choice("a", conv, _gets_fn) do
    mark_reviewed(conv.id)
    :accepted
  end

  defp apply_review_choice("e", conv, gets_fn) do
    new_text = gets_fn.("  New description: ") |> to_string() |> String.trim()
    if new_text != "", do: update_convention_text(conv.id, new_text)
    mark_reviewed(conv.id)
    :edited
  end

  defp apply_review_choice("r", conv, _gets_fn) do
    delete_convention(conv.id)
    :rejected
  end

  defp apply_review_choice(_, conv, _gets_fn) do
    mark_reviewed(conv.id)
    :accepted
  end

  defp mark_reviewed(id) when is_integer(id) do
    case Repo.get(Entry, id) do
      nil ->
        :ok

      entry ->
        meta = update_metadata(entry.metadata, %{"reviewed" => true})
        entry |> Ecto.Changeset.change(metadata: meta) |> Repo.update()
    end
  end

  defp mark_reviewed(_), do: :ok

  defp update_convention_text(id, new_text) when is_integer(id) do
    case Repo.get(Entry, id) do
      nil -> :ok
      entry -> entry |> Ecto.Changeset.change(text: new_text) |> Repo.update()
    end
  end

  defp update_convention_text(_, _), do: :ok

  defp delete_convention(id) when is_integer(id) do
    case Repo.get(Entry, id) do
      nil -> :ok
      entry -> Repo.delete(entry)
    end
  end

  defp delete_convention(_), do: :ok

  defp update_metadata(metadata_json, updates) do
    meta =
      case Jason.decode(metadata_json || "{}") do
        {:ok, decoded} -> decoded
        {:error, _} -> %{}
      end

    Map.merge(meta, updates) |> Jason.encode!()
  end
end
