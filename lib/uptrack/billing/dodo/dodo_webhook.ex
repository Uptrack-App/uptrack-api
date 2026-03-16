defmodule Uptrack.Billing.Dodo.DodoWebhook do
  @moduledoc """
  Dodo Payments webhook signature verification using the Standard Webhooks spec.

  Headers: webhook-id, webhook-signature, webhook-timestamp
  Signature: HMAC-SHA256 of "{msg_id}.{timestamp}.{body}", base64-encoded.
  Secret: base64-encoded key (strip "whsec_" prefix if present).
  """

  @tolerance_seconds 300

  def verify(raw_body, headers) do
    with {:ok, msg_id} <- get_header(headers, "webhook-id"),
         {:ok, signature} <- get_header(headers, "webhook-signature"),
         {:ok, timestamp} <- get_header(headers, "webhook-timestamp"),
         :ok <- verify_timestamp(timestamp) do
      secret = webhook_secret()
      signed_payload = "#{msg_id}.#{timestamp}.#{raw_body}"

      expected =
        :crypto.mac(:hmac, :sha256, secret, signed_payload)
        |> Base.encode64()

      # webhook-signature can contain multiple space-separated signatures (v1,xxx)
      signatures =
        signature
        |> String.split(" ")
        |> Enum.map(fn sig ->
          case String.split(sig, ",", parts: 2) do
            [_version, value] -> value
            [value] -> value
          end
        end)

      if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  defp get_header(headers, key) do
    case headers do
      %{^key => value} when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error, :missing_signature}
    end
  end

  defp verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        now = System.system_time(:second)

        if abs(now - ts) <= @tolerance_seconds do
          :ok
        else
          {:error, :timestamp_too_old}
        end

      _ ->
        {:error, :invalid_timestamp}
    end
  end

  defp webhook_secret do
    config = Application.get_env(:uptrack, :dodo) || %{}
    raw_secret = config[:webhook_secret] || raise "DODO_WEBHOOK_SECRET not configured"

    # Standard Webhooks secrets may be prefixed with "whsec_"
    raw_secret
    |> String.replace_leading("whsec_", "")
    |> Base.decode64!()
  end
end
