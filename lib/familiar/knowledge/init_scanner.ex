defmodule Familiar.Knowledge.InitScanner do
  @moduledoc """
  Project initialization scanner.

  Walks the project file tree, classifies files, extracts knowledge
  via LLM, and stores entries with embeddings. Orchestrates the full
  init pipeline: scan → classify → extract → embed → store.
  """

  require Logger

  alias Familiar.Knowledge
  alias Familiar.Knowledge.DefaultFiles
  alias Familiar.Knowledge.Extractor
  alias Familiar.Knowledge.FileClassifier

  @default_max_files 200
  @large_project_threshold 500

  @doc """
  Scan project files, classify them, and return file info structs.

  Options:
  - `:max_files` — maximum files to extract (default: 200)
  - `:file_system` — FileSystem implementation (default: from app config)
  """
  @spec scan_files(String.t(), keyword()) :: {:ok, [map()], non_neg_integer()}
  def scan_files(project_dir, opts \\ []) do
    max_files = Keyword.get(opts, :max_files, @default_max_files)
    fs = file_system(opts)

    all_files =
      project_dir
      |> walk_tree(fs)
      |> Enum.map(&Path.relative_to(&1, project_dir))
      |> Enum.filter(&(FileClassifier.classify(&1) == :index))

    {files, deferred} =
      if length(all_files) > @large_project_threshold do
        FileClassifier.prioritize_with_info(all_files, max_files)
      else
        {all_files, 0}
      end

    file_infos =
      files
      |> Enum.flat_map(fn rel_path ->
        abs_path = Path.join(project_dir, rel_path)

        case fs.read(abs_path) do
          {:ok, content} ->
            [%{relative_path: rel_path, content: content, absolute_path: abs_path}]

          {:error, reason} ->
            Logger.warning(
              "[InitScanner] Skipping unreadable file #{rel_path}: #{inspect(reason)}"
            )

            []
        end
      end)

    {:ok, file_infos, deferred}
  end

  @doc """
  Run the full init pipeline: scan → extract → embed → store.

  Options:
  - `:max_files` — maximum files to scan (default: 200)
  - `:progress_fn` — callback for progress reporting `(String.t() -> :ok)`
  - `:concurrency` — max concurrent embedding operations (default: 10)
  - `:file_system` — FileSystem implementation (default: from app config)
  """
  @spec run(String.t(), keyword()) ::
          {:ok, map()} | {:error, {atom(), map()}}
  def run(project_dir, opts \\ []) do
    progress_fn = Keyword.get(opts, :progress_fn, &default_progress/1)
    concurrency = Keyword.get(opts, :concurrency, 10)

    progress_fn.("Scanning files...")

    familiar_dir = Path.join(project_dir, ".familiar")

    with {:ok, files, deferred} <- scan_files(project_dir, opts) do
      result =
        if files == [] do
          {:ok,
           %{
             files_scanned: 0,
             entries_created: 0,
             deferred: deferred,
             warning: "No source files found to index — Familiar will have limited context"
           }}
        else
          run_extraction_pipeline(files, deferred, progress_fn, concurrency)
        end

      with {:ok, summary} <- result do
        DefaultFiles.install(familiar_dir)
        {:ok, summary}
      end
    end
  end

  @doc """
  Run a function with atomic cleanup — if the function returns an error,
  raises, or the process receives SIGINT/SIGTERM, delete the `.familiar/`
  directory to prevent partial state.

  Used by the CLI init command to ensure FR7b: no partial state on interrupt.
  """
  @spec run_with_cleanup(String.t(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, {atom(), map()}}
  def run_with_cleanup(project_dir, fun) do
    familiar_dir = Path.join(project_dir, ".familiar")
    caller = self()

    # Trap SIGINT and SIGTERM for atomic cleanup
    cleanup_ref = trap_signals(familiar_dir, caller)

    try do
      case fun.() do
        {:ok, _} = success ->
          success

        {:error, _} = error ->
          cleanup_familiar_dir(familiar_dir)
          error
      end
    rescue
      e ->
        cleanup_familiar_dir(familiar_dir)
        {:error, {:init_failed, %{reason: Exception.message(e)}}}
    catch
      :exit, reason ->
        cleanup_familiar_dir(familiar_dir)
        {:error, {:init_failed, %{reason: inspect(reason)}}}
    after
      untrap_signals(cleanup_ref)
    end
  end

  # -- Private --

  defp trap_signals(familiar_dir, _caller) do
    [:sigterm, :sigquit]
    |> Enum.flat_map(&trap_signal(&1, familiar_dir))
  end

  defp trap_signal(signal, familiar_dir) do
    case System.trap_signal(signal, fn -> cleanup_familiar_dir(familiar_dir) end) do
      {:ok, ref} -> [{signal, ref}]
      _ -> []
    end
  end

  defp untrap_signals(refs) do
    Enum.each(refs, fn {signal, ref} ->
      System.untrap_signal(signal, ref)
    end)
  end

  defp cleanup_familiar_dir(familiar_dir) do
    if File.dir?(familiar_dir) do
      File.rm_rf!(familiar_dir)
    end
  end

  defp run_extraction_pipeline(files, deferred, progress_fn, concurrency) do
    progress_fn.("Extracting knowledge from #{length(files)} files...")

    {entries, extraction_failures} = Extractor.extract_from_files_with_stats(files)

    if extraction_failures > 0 do
      Logger.warning(
        "[InitScanner] #{extraction_failures} file(s) failed knowledge extraction (LLM unavailable or returned invalid response)"
      )
    end

    progress_fn.("Building knowledge store (embedding 0/#{length(entries)} entries)...")

    results = embed_entries(entries, progress_fn, concurrency)

    created = Enum.count(results, &match?({:ok, _}, &1))

    summary = %{
      files_scanned: length(files),
      entries_created: created,
      deferred: deferred
    }

    summary =
      if extraction_failures > 0 do
        Map.put(
          summary,
          :extraction_warnings,
          "#{extraction_failures} file(s) could not be analyzed by LLM"
        )
      else
        summary
      end

    {:ok, summary}
  end

  defp embed_entries(entries, progress_fn, concurrency) do
    total = length(entries)
    counter = :counters.new(1, [:atomics])

    entries
    |> Task.async_stream(
      fn entry_attrs ->
        result = Knowledge.store_with_embedding(entry_attrs)
        :counters.add(counter, 1, 1)
        idx = :counters.get(counter, 1)
        progress_fn.("Building knowledge store (embedding #{idx}/#{total} entries)...")
        result
      end,
      max_concurrency: concurrency,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:embedding_failed, %{reason: inspect(reason)}}}
    end)
  end

  defp walk_tree(dir, fs) do
    case fs.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, &walk_entry(dir, &1, fs))

      {:error, _} ->
        []
    end
  end

  defp walk_entry(dir, entry, fs) do
    full_path = Path.join(dir, entry)

    cond do
      File.dir?(full_path) and FileClassifier.classify(entry <> "/") != :skip ->
        walk_tree(full_path, fs)

      File.regular?(full_path) ->
        [full_path]

      true ->
        []
    end
  end

  defp file_system(opts) do
    Keyword.get_lazy(opts, :file_system, fn ->
      Application.get_env(:familiar, Familiar.System.FileSystem, Familiar.System.LocalFileSystem)
    end)
  end

  defp default_progress(_msg), do: :ok
end
