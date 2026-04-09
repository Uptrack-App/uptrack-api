defmodule Uptrack.Alerting.AckToken do
  @moduledoc """
  Signs and verifies one-click acknowledge tokens embedded in alert messages.
  Tokens are valid for 7 days and encode only the incident ID.
  """

  @salt "incident_ack"
  @max_age 7 * 24 * 3600

  def sign(incident_id) do
    Phoenix.Token.sign(UptrackWeb.Endpoint, @salt, incident_id)
  end

  def verify(token) do
    Phoenix.Token.verify(UptrackWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end
