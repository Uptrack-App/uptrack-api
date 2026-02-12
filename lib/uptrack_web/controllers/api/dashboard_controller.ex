defmodule UptrackWeb.Api.DashboardController do
  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  def stats(conn, _params) do
    org = conn.assigns.current_organization
    stats = Monitoring.get_dashboard_stats(org.id)
    json(conn, %{data: stats})
  end
end
