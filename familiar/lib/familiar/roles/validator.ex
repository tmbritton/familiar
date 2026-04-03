defmodule Familiar.Roles.Validator do
  @moduledoc """
  Validates role and skill cross-references.

  Checks that roles reference existing skill files and that skills
  reference known tools (with warnings for unknown tools).
  """

  require Logger

  alias Familiar.Roles.{Role, Skill}

  @mvp_tools ~w(
    read_file write_file list_files search_files
    run_shell search_context store_context
  )

  @doc """
  Validates a role's skill references exist on disk.

  Returns `:ok` or `{:error, {:invalid_role, %{name, reason}}}`.
  """
  @spec validate_role(Role.t(), keyword()) :: :ok | {:error, {:invalid_role, map()}}
  def validate_role(%Role{} = role, opts \\ []) do
    familiar_dir = Keyword.fetch!(opts, :familiar_dir)
    skills_dir = Path.join(familiar_dir, "skills")

    missing =
      role.skills
      |> Enum.reject(fn skill_name ->
        Path.join(skills_dir, "#{skill_name}.md") |> File.exists?()
      end)

    case missing do
      [] ->
        :ok

      names ->
        reason =
          Enum.map_join(
            names,
            "; ",
            &"references skill '#{&1}' which does not exist in .familiar/skills/"
          )

        {:error, {:invalid_role, %{name: role.name, reason: reason}}}
    end
  end

  @doc """
  Validates a skill's tool references against the known tool list.

  Unknown tools produce a warning but the skill remains valid.
  Returns `:ok` always (tools are forward-declarable).
  """
  @spec validate_skill(Skill.t(), keyword()) :: :ok
  def validate_skill(%Skill{} = skill, opts \\ []) do
    known_tools = Keyword.get(opts, :known_tools, @mvp_tools)

    unknown = Enum.reject(skill.tools, &(&1 in known_tools))

    for tool <- unknown do
      Logger.warning(
        "Skill '#{skill.name}' references unknown tool '#{tool}' — " <>
          "it may not be registered yet"
      )
    end

    :ok
  end

  @doc "Returns the default MVP tool list."
  @spec mvp_tools() :: [String.t()]
  def mvp_tools, do: @mvp_tools
end
