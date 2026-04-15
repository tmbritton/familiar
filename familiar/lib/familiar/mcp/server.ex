defmodule Familiar.MCP.Server do
  @moduledoc """
  Ecto schema for persisted MCP server configurations.

  Each row represents a single MCP server that Familiar can launch as a
  subprocess. The `args_json` and `env_json` fields store JSON-encoded
  lists/maps respectively. Env values support `${VAR}` interpolation,
  resolved at client launch time via `Familiar.Config.expand_env/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @name_format ~r/^[a-z][a-z0-9_-]*$/

  schema "mcp_servers" do
    field :name, :string
    field :command, :string
    field :args_json, :string, default: "[]"
    field :env_json, :string, default: "{}"
    field :disabled, :boolean, default: false
    field :read_only, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc "Build a changeset for creating or updating an MCP server."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(server, attrs) do
    server
    |> cast(attrs, [:name, :command, :args_json, :env_json, :disabled, :read_only])
    |> validate_required([:name, :command])
    |> validate_format(:name, @name_format,
      message:
        "must start with a lowercase letter and contain only lowercase letters, digits, hyphens, and underscores"
    )
    |> validate_name_not_reserved_prefix()
    |> validate_name_not_builtin()
    |> validate_json_field(:args_json, :list, "must be a valid JSON array")
    |> validate_json_field(:env_json, :map, "must be a valid JSON object")
    |> unique_constraint(:name)
  end

  defp validate_name_not_reserved_prefix(changeset) do
    name = get_change(changeset, :name)

    if is_binary(name) and String.starts_with?(name, "fam_") do
      add_error(changeset, :name, "prefix 'fam_' is reserved for built-in tools")
    else
      changeset
    end
  end

  defp validate_name_not_builtin(changeset) do
    name = get_change(changeset, :name)

    if is_binary(name) do
      builtin_names = fetch_builtin_names()

      if name in builtin_names do
        add_error(changeset, :name, "collides with built-in tool '#{name}'")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp fetch_builtin_names do
    registry = Application.get_env(:familiar, :tool_registry, Familiar.Execution.ToolRegistry)
    registry.list_tools() |> Enum.map(& &1.name) |> Enum.map(&to_string/1)
  rescue
    _ -> []
  end

  defp validate_json_field(changeset, field, expected_type, message) do
    value = get_field(changeset, field)

    if is_binary(value) do
      case Jason.decode(value) do
        {:ok, decoded} -> validate_json_type(changeset, field, decoded, expected_type, message)
        {:error, _} -> add_error(changeset, field, message)
      end
    else
      changeset
    end
  end

  defp validate_json_type(changeset, _field, decoded, :list, _message) when is_list(decoded),
    do: changeset

  defp validate_json_type(changeset, _field, decoded, :map, _message) when is_map(decoded),
    do: changeset

  defp validate_json_type(changeset, field, _decoded, _expected, message),
    do: add_error(changeset, field, message)
end
