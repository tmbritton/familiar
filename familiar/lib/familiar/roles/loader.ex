defmodule Familiar.Roles.Loader do
  @moduledoc """
  Loads and parses role and skill markdown files with YAML frontmatter.
  """

  alias Familiar.Roles.{Role, Skill}

  @doc """
  Parses a markdown file into frontmatter map and body string.

  Returns `{:ok, %{frontmatter: map, body: string}}` or `{:error, reason}`.
  """
  @spec parse_file(String.t()) ::
          {:ok, %{frontmatter: map(), body: String.t()}} | {:error, term()}
  def parse_file(path) do
    with {:ok, content} <- read_file(path),
         {:ok, frontmatter, body} <- split_frontmatter(content) do
      {:ok, %{frontmatter: frontmatter, body: String.trim(body)}}
    end
  end

  @doc "Builds a `%Role{}` from parsed frontmatter and body."
  @spec build_role(%{frontmatter: map(), body: String.t()}) ::
          {:ok, Role.t()} | {:error, {:invalid_role, map()}}
  def build_role(%{frontmatter: fm, body: body}) do
    with :ok <- require_fields(fm, ~w(name description skills), :invalid_role),
         :ok <- validate_string_fields(fm, ~w(name description), :invalid_role),
         :ok <- validate_list_of_strings(fm, "skills", :invalid_role) do
      name = Map.fetch!(fm, "name")

      case parse_lifecycle(fm) do
        {:ok, lifecycle} ->
          {:ok,
           %Role{
             name: name,
             description: Map.fetch!(fm, "description"),
             model: Map.get(fm, "model", "default"),
             lifecycle: lifecycle,
             skills: List.wrap(Map.fetch!(fm, "skills")),
             system_prompt: body
           }}

        {:error, reason} ->
          {:error, {:invalid_role, %{name: name, reason: reason}}}
      end
    end
  end

  @doc "Builds a `%Skill{}` from parsed frontmatter and body."
  @spec build_skill(%{frontmatter: map(), body: String.t()}) ::
          {:ok, Skill.t()} | {:error, {:invalid_skill, map()}}
  def build_skill(%{frontmatter: fm, body: body}) do
    with :ok <- require_fields(fm, ~w(name description tools), :invalid_skill),
         :ok <- validate_string_fields(fm, ~w(name description), :invalid_skill),
         :ok <- validate_list_of_strings(fm, "tools", :invalid_skill),
         :ok <- validate_constraints(fm) do
      {:ok,
       %Skill{
         name: Map.fetch!(fm, "name"),
         description: Map.fetch!(fm, "description"),
         tools: List.wrap(Map.fetch!(fm, "tools")),
         constraints: Map.get(fm, "constraints", %{}),
         instructions: body
       }}
    end
  end

  # -- Private --

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, {:file_not_found, path}}
      {:error, reason} -> {:error, {:file_read_error, %{path: path, reason: reason}}}
    end
  end

  defp split_frontmatter(content) do
    case Regex.split(~r/^---\s*$/m, content, parts: 3) do
      [_, yaml, body] ->
        case YamlElixir.read_from_string(yaml) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed, body}
          {:ok, _} -> {:error, {:malformed_frontmatter, "frontmatter must be a YAML mapping"}}
          {:error, _} -> {:error, {:malformed_frontmatter, "invalid YAML syntax"}}
        end

      _ ->
        {:error, {:malformed_frontmatter, "missing --- frontmatter delimiters"}}
    end
  end

  defp require_fields(fm, required, error_type) do
    missing = Enum.filter(required, &(not Map.has_key?(fm, &1)))

    case missing do
      [] ->
        :ok

      fields ->
        name = Map.get(fm, "name", "unknown")
        reason = "missing required field(s): #{Enum.join(fields, ", ")}"
        {:error, {error_type, %{name: name, reason: reason}}}
    end
  end

  defp validate_string_fields(fm, fields, error_type) do
    bad = Enum.reject(fields, fn field -> is_binary(Map.get(fm, field)) end)

    case bad do
      [] ->
        :ok

      _ ->
        name = Map.get(fm, "name", "unknown")

        {:error,
         {error_type, %{name: name, reason: "field(s) must be strings: #{Enum.join(bad, ", ")}"}}}
    end
  end

  defp validate_list_of_strings(fm, field, error_type) do
    value = Map.get(fm, field)

    valid? =
      cond do
        is_binary(value) -> true
        is_list(value) -> Enum.all?(value, &is_binary/1)
        true -> false
      end

    if valid? do
      :ok
    else
      name = Map.get(fm, "name", "unknown")

      {:error,
       {error_type, %{name: name, reason: "'#{field}' must be a string or list of strings"}}}
    end
  end

  defp validate_constraints(fm) do
    case Map.get(fm, "constraints") do
      nil ->
        :ok

      value when is_map(value) ->
        :ok

      _ ->
        name = Map.get(fm, "name", "unknown")
        {:error, {:invalid_skill, %{name: name, reason: "'constraints' must be a mapping"}}}
    end
  end

  defp parse_lifecycle(fm) do
    case Map.get(fm, "lifecycle") do
      nil ->
        {:ok, :ephemeral}

      value when is_binary(value) ->
        case Map.fetch(Role.valid_lifecycles(), value) do
          {:ok, atom} ->
            {:ok, atom}

          :error ->
            {:error, "invalid lifecycle '#{value}'; must be one of: ephemeral, batch, session"}
        end

      _ ->
        {:error, "lifecycle must be a string"}
    end
  end
end
