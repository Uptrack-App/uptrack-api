defmodule Uptrack.TestSupport.RaisingMailerAdapter do
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config) do
    raise "mailer exploded"
  end
end
