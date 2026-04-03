defmodule Familiar.Roles.Skill do
  @moduledoc """
  Struct representing a skill loaded from a markdown file.

  Skill files live in `.familiar/skills/` and define a capability bundle
  with tool requirements, constraints, and instruction text.
  """

  @enforce_keys [:name, :description, :tools, :instructions]
  defstruct [
    :name,
    :description,
    :instructions,
    tools: [],
    constraints: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          tools: [String.t()],
          constraints: map(),
          instructions: String.t()
        }
end
