defmodule UptrackWeb.Api.SlackCommandController do
  @moduledoc """
  Handles Slack slash commands (e.g. /uptrack status, /uptrack list).
  Verifies the request signature from Slack before processing.
  """

  use UptrackWeb, :controller

  alias Uptrack.Monitoring

  require Logger

  def handle(conn, params) do
    case verify_slack_signature(conn) do
      :ok ->
        response = execute_command(params)
        json(conn, response)

      {:error, reason} ->
        Logger.warning("Slack command signature verification failed: #{reason}")
        conn |> put_status(401) |> json(%{error: "Invalid signature"})
    end
  end

  defp execute_command(%{"text" => text} = params) do
    command = text |> String.trim() |> String.downcase()
    team_id = params["team_id"]

    case command do
      "status" -> status_command(team_id)
      "list" -> list_command(team_id)
      "help" -> help_response()
      "" -> help_response()
      _ -> %{response_type: "ephemeral", text: "Unknown command: `#{text}`. Try `/uptrack help`"}
    end
  end

  defp execute_command(_), do: help_response()

  defp status_command(team_id) do
    case find_org_by_slack_team(team_id) do
      nil -> not_connected_response()
      org ->
        monitors = Monitoring.list_monitors(org.id)
        total = length(monitors)
        down_monitors = Enum.filter(monitors, &(Map.get(&1, :last_check_status) == "down"))
        down = length(down_monitors)
        paused = Enum.count(monitors, &(&1.status == "paused"))
        up = total - down - paused

        header = "*Monitoring Status* — #{total} monitors"

        summary =
          if down == 0 do
            ":large_green_circle: All #{total} monitors operational."
          else
            counts = ":large_green_circle: #{up} up  :red_circle: #{down} down" <>
              if(paused > 0, do: "  :yellow_circle: #{paused} paused", else: "")

            down_list =
              down_monitors
              |> Enum.take(10)
              |> Enum.map(fn m -> ":red_circle: *#{m.name || m.url}*" end)
              |> Enum.join("\n")

            suffix = if down > 10, do: "\n_...and #{down - 10} more_", else: ""

            counts <> "\n\n*Down right now:*\n" <> down_list <> suffix
          end

        %{response_type: "in_channel", text: header <> "\n" <> summary}
    end
  end

  defp list_command(team_id) do
    case find_org_by_slack_team(team_id) do
      nil -> not_connected_response()
      org ->
        monitors = Monitoring.list_monitors(org.id) |> Enum.take(20)

        if monitors == [] do
          %{response_type: "ephemeral", text: "No monitors found. Create one at https://uptrack.app/dashboard/monitors/new"}
        else
          lines =
            monitors
            |> Enum.map(fn m ->
              status_icon = if Map.get(m, :last_check_status) == "down", do: ":red_circle:", else: ":large_green_circle:"
              "#{status_icon} *#{m.name || m.url}* — `#{m.interval}s` — #{m.url}"
            end)
            |> Enum.join("\n")

          %{response_type: "ephemeral", text: lines}
        end
    end
  end

  defp help_response do
    %{
      response_type: "ephemeral",
      text: """
      */uptrack* — Uptrack monitoring commands

      `/uptrack status` — Show monitoring overview (up/down counts)
      `/uptrack list` — List your monitors
      `/uptrack help` — Show this help

      Manage monitors at https://uptrack.app/dashboard
      """
    }
  end

  defp not_connected_response do
    %{
      response_type: "ephemeral",
      text: "This workspace isn't connected to an Uptrack account. Connect Slack from https://uptrack.app/dashboard/alerts"
    }
  end

  defp find_org_by_slack_team(team_id) when is_binary(team_id) do
    import Ecto.Query

    Uptrack.AppRepo.one(
      from ac in Uptrack.Monitoring.AlertChannel,
        where: ac.type == :slack,
        where: fragment("? ->> 'team_id' = ?", ac.config, ^team_id),
        select: %{id: ac.organization_id},
        limit: 1
    )
  end

  defp find_org_by_slack_team(_), do: nil

  # --- Slack signature verification ---

  defp verify_slack_signature(conn) do
    signing_secret = Application.get_env(:uptrack, :slack_signing_secret)

    if is_nil(signing_secret) do
      # Skip verification in dev/test if not configured
      :ok
    else
      timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first()
      signature = get_req_header(conn, "x-slack-signature") |> List.first()

      with true <- is_binary(timestamp) and is_binary(signature),
           {ts, _} <- Integer.parse(timestamp),
           true <- abs(System.os_time(:second) - ts) < 300 do
        body = conn.assigns[:raw_body] || ""
        base = "v0:#{timestamp}:#{body}"
        expected = "v0=" <> :crypto.mac(:hmac, :sha256, signing_secret, base) |> Base.encode16(case: :lower)

        if Plug.Crypto.secure_compare(expected, signature) do
          :ok
        else
          {:error, "signature mismatch"}
        end
      else
        _ -> {:error, "invalid timestamp or signature"}
      end
    end
  end
end
