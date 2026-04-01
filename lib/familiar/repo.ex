defmodule Familiar.Repo do
  use Ecto.Repo,
    otp_app: :familiar,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  Load the sqlite-vec extension on every database connection.
  """
  @impl true
  def init(_type, config) do
    config = Keyword.put(config, :load_extensions, [SqliteVec.path()])
    {:ok, config}
  end
end
