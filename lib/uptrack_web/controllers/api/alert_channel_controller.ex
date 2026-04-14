defmodule UptrackWeb.Api.AlertChannelController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Monitoring
  alias Uptrack.Alerting
  alias Uptrack.Teams

  action_fallback UptrackWeb.Api.FallbackController

  def index(conn, _params) do
    org = conn.assigns.current_organization
    channels = Monitoring.list_alert_channels(org.id)
    render(conn, :index, alert_channels: channels)
  end

  def allowed_types(conn, _params) do
    org = conn.assigns.current_organization
    allowed = Billing.allowed_channel_types(org.plan)

    json(conn, %{
      allowed: allowed,
      plan: org.plan
    })
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    channel_type = params["type"]

    with :ok <- check_limit(org, :alert_channels),
         :ok <- check_channel_type_allowed(org, channel_type) do
      attrs =
        params
        |> Map.put("organization_id", org.id)
        |> Map.put("user_id", user.id)

      case Monitoring.create_alert_channel(attrs) do
        {:ok, channel} ->
          Teams.log_action_from_conn(conn, "alert_channel.created", "alert_channel", channel.id,
            metadata: %{name: channel.name, type: channel.type}
          )

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

  defp check_channel_type_allowed(org, channel_type) do
    allowed = Billing.allowed_channel_types(org.plan)

    if channel_type in allowed do
      :ok
    else
      {:error, :plan_limit,
       "#{channel_type} is not a supported alert channel type. Supported: #{Enum.join(allowed, ", ")}."}
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
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Monitoring.update_alert_channel(channel, params) do
        {:ok, updated} ->
          Teams.log_action_from_conn(conn, "alert_channel.updated", "alert_channel", updated.id,
            metadata: %{name: updated.name}
          )

          render(conn, :show, alert_channel: updated)

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def delete(conn, %{"id" => id}) do
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Monitoring.delete_alert_channel(channel) do
        {:ok, _} ->
          Teams.log_action_from_conn(conn, "alert_channel.deleted", "alert_channel", channel.id,
            metadata: %{name: channel.name}
          )

          send_resp(conn, :no_content, "")

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def test(conn, %{"id" => id}) do
    _user = conn.assigns.current_user
    org = conn.assigns.current_organization

    channel = Monitoring.get_alert_channel!(id)

    if channel.organization_id == org.id do
      case Alerting.send_test_alert(channel) do
        {:ok, _} ->
          Teams.log_action_from_conn(conn, "alert_channel.tested", "alert_channel", channel.id,
            metadata: %{name: channel.name}
          )

          json(conn, %{ok: true})
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
