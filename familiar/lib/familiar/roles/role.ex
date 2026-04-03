defmodule Familiar.Roles.Role do
  @moduledoc """
  Struct representing an agent role loaded from a markdown file.

  Role files live in `.familiar/roles/` and define an agent's persona,
  model preference, lifecycle strategy, required skills, and system prompt.
  """

  @enforce_keys [:name, :description, :skills, :system_prompt]
  defstruct [
    :name,
    :description,
    :system_prompt,
    model: "default",
    lifecycle: :ephemeral,
    skills: []
  ]

  @type lifecycle :: :ephemeral | :batch | :session

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          model: String.t(),
          lifecycle: lifecycle(),
          skills: [String.t()],
          system_prompt: String.t()
        }

  @valid_lifecycles %{
    "ephemeral" => :ephemeral,
    "batch" => :batch,
    "session" => :session
  }

  @doc "Map of valid lifecycle string values to their atom equivalents."
  @spec valid_lifecycles() :: %{String.t() => lifecycle()}
  def valid_lifecycles, do: @valid_lifecycles
end
