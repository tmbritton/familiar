defmodule Familiar.System.FileSystem do
  @moduledoc """
  Behaviour for filesystem operations.

  Abstracts file I/O so tests can use an in-memory mock instead of
  touching the real filesystem.
  """

  @type path :: String.t()
  @type stat_result :: %{mtime: DateTime.t(), size: non_neg_integer()}

  @doc "Read the contents of a file."
  @callback read(path()) :: {:ok, binary()} | {:error, {atom(), map()}}

  @doc "Write content to a file, creating parent directories as needed."
  @callback write(path(), content :: binary()) :: :ok | {:error, {atom(), map()}}

  @doc "Return file metadata (mtime, size)."
  @callback stat(path()) :: {:ok, stat_result()} | {:error, {atom(), map()}}

  @doc "Delete a file."
  @callback delete(path()) :: :ok | {:error, {atom(), map()}}

  @doc "List files in a directory."
  @callback ls(path()) :: {:ok, [String.t()]} | {:error, {atom(), map()}}
end
