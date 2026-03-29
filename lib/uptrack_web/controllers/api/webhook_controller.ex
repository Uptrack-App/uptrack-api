defmodule UptrackWeb.Api.WebhookController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  require Logger

  # --- Paddle webhooks ---

  def paddle(conn, _params) do
    with {:ok, raw_body} <- get_raw_body(conn),
         :ok <- verify_paddle_signature(conn, raw_body),
         {:ok, payload} <- Jason.decode(raw_body) do
      event_type = payload["event_type"]
      event_data = payload["data"] || %{}

      Logger.info("Paddle webhook: #{event_type}")
      Billing.handle_webhook_event(event_type, event_data)

      json(conn, %{received: true})
    else
      {:error, :missing_signature} ->
        conn |> put_status(401) |> json(%{error: "Missing signature"})

      {:error, :invalid_signature} ->
        conn |> put_status(401) |> json(%{error: "Invalid signature"})

      {:error, reason} ->
        Logger.error("Paddle webhook processing error: #{inspect(reason)}")
        conn |> put_status(400) |> json(%{error: "Bad request"})
    end
  end

  # --- Paddle signature verification ---

  defp verify_paddle_signature(conn, raw_body) do
    case Plug.Conn.get_req_header(conn, "paddle-signature") do
      [paddle_signature] ->
        with {:ok, ts, h1} <- parse_paddle_signature(paddle_signature) do
          secret = paddle_webhook_secret()
          signed_payload = "#{ts}:#{raw_body}"

          expected =
            :crypto.mac(:hmac, :sha256, secret, signed_payload)
            |> Base.encode16(case: :lower)

          if Plug.Crypto.secure_compare(expected, h1) do
            :ok
          else
            {:error, :invalid_signature}
          end
        end

      _ ->
        {:error, :missing_signature}
    end
  end

  defp parse_paddle_signature(header) do
    parts = String.split(header, ";")

    with ts when is_binary(ts) <- find_part(parts, "ts="),
         h1 when is_binary(h1) <- find_part(parts, "h1=") do
      {:ok, ts, h1}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp find_part(parts, prefix) do
    Enum.find_value(parts, fn part ->
      if String.starts_with?(part, prefix) do
        String.trim_leading(part, prefix)
      end
    end)
  end

  defp get_raw_body(conn) do
    case conn.private[:raw_body] do
      nil -> {:error, :no_raw_body}
      body -> {:ok, body}
    end
  end

  defp paddle_webhook_secret do
    config = Application.get_env(:uptrack, :paddle) || %{}
    config[:webhook_secret] || raise "PADDLE_WEBHOOK_SECRET not configured"
  end
end
