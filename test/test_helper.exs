ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Uptrack.AppRepo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Uptrack.ObanRepo, :manual)
{:ok, _} = Uptrack.SMTP.FakeSMTPState.start_link([])
