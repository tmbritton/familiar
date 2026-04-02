defmodule Familiar.System.LocalFileSystem do
  @moduledoc """
  Production adapter for the FileSystem behaviour.

  Delegates to the standard `File` module.
  """

  @behaviour Familiar.System.FileSystem

  @impl true
  def read(path) do
    case File.read(path) do
      {:ok, _} = success -> success
      {:error, reason} -> {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end

  @impl true
  def write(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end

  @impl true
  def stat(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime, size: size}} ->
        {:ok, %{mtime: mtime, size: size}}

      {:error, reason} ->
        {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end

  @impl true
  def delete(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end

  @impl true
  def ls(path) do
    case File.ls(path) do
      {:ok, _} = success -> success
      {:error, reason} -> {:error, {:file_error, %{path: path, reason: reason}}}
    end
  end
end
