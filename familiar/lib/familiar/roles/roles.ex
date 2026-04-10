defmodule Familiar.Roles do
  @moduledoc """
  Public API for loading and validating agent roles and skills from markdown files.

  Role files live in `.familiar/roles/` and skill files in `.familiar/skills/`.
  Each file has YAML frontmatter and a markdown body used as the system prompt
  (roles) or instruction text (skills).
  """

  use Boundary, deps: [], exports: [Familiar.Roles]

  require Logger

  alias Familiar.Daemon.Paths
  alias Familiar.Roles.{Loader, Role, Skill, Validator}

  @doc """
  Loads a role by name from the roles directory.

  ## Options

    * `:familiar_dir` - path to `.familiar/` directory (default: `Paths.familiar_dir/0`)

  Returns `{:ok, %Role{}}` or `{:error, {atom, map}}`.
  """
  @spec load_role(String.t(), keyword()) :: {:ok, Role.t()} | {:error, term()}
  def load_role(name, opts \\ []) do
    with :ok <- validate_name(name, :role) do
      path = role_path(name, opts)

      with {:ok, parsed} <- Loader.parse_file(path),
           {:ok, role} <- Loader.build_role(parsed) do
        {:ok, role}
      else
        {:error, {:file_not_found, _}} ->
          {:error, {:role_not_found, %{name: name}}}

        {:error, {:malformed_frontmatter, reason}} ->
          {:error, {:invalid_role, %{name: name, reason: reason}}}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Loads a skill by name from the skills directory.

  ## Options

    * `:familiar_dir` - path to `.familiar/` directory (default: `Paths.familiar_dir/0`)

  Returns `{:ok, %Skill{}}` or `{:error, {atom, map}}`.
  """
  @spec load_skill(String.t(), keyword()) :: {:ok, Skill.t()} | {:error, term()}
  def load_skill(name, opts \\ []) do
    with :ok <- validate_name(name, :skill) do
      path = skill_path(name, opts)

      with {:ok, parsed} <- Loader.parse_file(path),
           {:ok, skill} <- Loader.build_skill(parsed) do
        {:ok, skill}
      else
        {:error, {:file_not_found, _}} ->
          {:error, {:skill_not_found, %{name: name}}}

        {:error, {:malformed_frontmatter, reason}} ->
          {:error, {:invalid_skill, %{name: name, reason: reason}}}

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Lists all valid roles in the roles directory.

  Invalid files are excluded and logged as warnings.

  ## Options

    * `:familiar_dir` - path to `.familiar/` directory
  """
  @spec list_roles(keyword()) :: {:ok, [Role.t()]}
  def list_roles(opts \\ []) do
    dir = roles_dir(opts)

    roles =
      dir
      |> glob_markdown()
      |> Enum.reduce([], fn path, acc ->
        name = Path.basename(path, ".md")

        case load_role(name, opts) do
          {:ok, role} ->
            [role | acc]

          {:error, reason} ->
            Logger.warning("Skipping invalid role file #{path}: #{inspect(reason)}")
            acc
        end
      end)
      |> Enum.reverse()

    {:ok, roles}
  end

  @doc """
  Lists all valid skills in the skills directory.

  Invalid files are excluded and logged as warnings.

  ## Options

    * `:familiar_dir` - path to `.familiar/` directory
  """
  @spec list_skills(keyword()) :: {:ok, [Skill.t()]}
  def list_skills(opts \\ []) do
    dir = skills_dir(opts)

    skills =
      dir
      |> glob_markdown()
      |> Enum.reduce([], fn path, acc ->
        name = Path.basename(path, ".md")

        case load_skill(name, opts) do
          {:ok, skill} ->
            [skill | acc]

          {:error, reason} ->
            Logger.warning("Skipping invalid skill file #{path}: #{inspect(reason)}")
            acc
        end
      end)
      |> Enum.reverse()

    {:ok, skills}
  end

  @doc """
  Validates a role including skill cross-references.

  Returns `:ok` or `{:error, {:invalid_role, %{name, reason}}}`.
  """
  @spec validate_role(String.t(), keyword()) ::
          :ok
          | {:error, {:invalid_role | :role_not_found | :file_read_error | :invalid_skill, map()}}
  def validate_role(name, opts \\ []) do
    with {:ok, role} <- load_role(name, opts) do
      Validator.validate_role(role, familiar_dir: familiar_dir(opts))
    end
  end

  @doc """
  Validates a skill including tool cross-references.

  Returns `:ok` (unknown tools produce warnings, not errors).
  """
  @spec validate_skill(String.t(), keyword()) ::
          :ok
          | {:error,
             {:invalid_skill | :skill_not_found | :file_read_error | :invalid_role, map()}}
  def validate_skill(name, opts \\ []) do
    with {:ok, skill} <- load_skill(name, opts) do
      Validator.validate_skill(skill, opts)
    end
  end

  # -- Private --

  defp familiar_dir(opts) do
    Keyword.get_lazy(opts, :familiar_dir, fn -> Paths.familiar_dir() end)
  end

  defp roles_dir(opts), do: Path.join(familiar_dir(opts), "roles")
  defp skills_dir(opts), do: Path.join(familiar_dir(opts), "skills")

  defp role_path(name, opts), do: Path.join(roles_dir(opts), "#{name}.md")
  defp skill_path(name, opts), do: Path.join(skills_dir(opts), "#{name}.md")

  defp glob_markdown(dir) do
    Path.join(dir, "*.md") |> Path.wildcard() |> Enum.sort()
  end

  defp validate_name(name, type) do
    if String.contains?(name, ["/", "\\", ".."]) do
      error_type = if type == :role, do: :invalid_role, else: :invalid_skill
      {:error, {error_type, %{name: name, reason: "invalid characters in name"}}}
    else
      :ok
    end
  end
end
