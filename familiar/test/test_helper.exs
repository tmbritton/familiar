ExUnit.configure(exclude: [:integration, :benchmark])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Familiar.Repo, :manual)
