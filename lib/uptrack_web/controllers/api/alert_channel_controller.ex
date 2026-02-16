defmodule UptrackWeb.Api.AlertChannelController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Monitoring
  alias Uptrack.Alerting

  action_fallback UptrackWeb.Api.FallbackController

  def index(conn, _params) do
    org = conn.assigns.current_organization
    channels = Monitoring.list_alert_channels(org.id)
    render(conn, :index, alert_channels: channels)
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    with :ok <- check_limit(org, :alert_channels) do
      attrs =
        params
        |> Map.put("organization_id", org.id)
        |> Map.put("user_id", user.id)

      case Monitoring.create_alert_channel(attrs) do
        {:ok, channel} ->
          conn
          |> put_status(:created)
          |> render(:show, alert_channel: channel)

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp check_limit(org, resource) do
    case Billing.check_plan_limit(org, resource) do
      :ok -> :ok
      {:error, message} -> {:error, :plan_limit, message}
    end
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      render(conn, :show, alert_channel: channel)
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def update(conn, %{"id" => id} = params) do
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Monitoring.update_alert_channel(channel, params) do
        {:ok, updated} -> render(conn, :show, alert_channel: updated)
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Monitoring.delete_alert_channel(channel) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def test(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Alerting.send_test_alert(channel) do
        {:ok, _} -> json(conn, %{ok: true})
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
