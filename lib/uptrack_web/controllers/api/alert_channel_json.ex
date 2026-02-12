defmodule UptrackWeb.Api.AlertChannelJSON do
  alias Uptrack.Monitoring.AlertChannel

  def index(%{alert_channels: channels}) do
    %{data: for(ch <- channels, do: channel_data(ch))}
  end

  def show(%{alert_channel: channel}) do
    %{data: channel_data(channel)}
  end

  defp channel_data(%AlertChannel{} = ch) do
    %{
      id: ch.id,
      name: ch.name,
      type: ch.type,
      config: ch.config,
      is_active: ch.is_active,
      inserted_at: ch.inserted_at,
      updated_at: ch.updated_at
    }
  end
end
