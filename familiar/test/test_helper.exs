ExUnit.configure(exclude: [:integration])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Familiar.Repo, :manual)
