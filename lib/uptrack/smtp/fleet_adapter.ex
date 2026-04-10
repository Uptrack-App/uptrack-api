defmodule Uptrack.SMTP.FleetAdapter do
  @moduledoc """
  Swoosh adapter that routes delivery through the SMTP connection fleet.
  Set via `config :uptrack, Uptrack.Mailer, adapter: Uptrack.SMTP.FleetAdapter`.
  """

  use Swoosh.Adapter, required_config: []

  @impl Swoosh.Adapter
  def deliver(%Swoosh.Email{} = email, _config) do
    Uptrack.SMTP.Fleet.deliver(email)
  end
end
