defmodule Uptrack.Billing.Creem.CreemWebhook do
  @moduledoc """
  Creem webhook signature verification.

  Creem signs webhooks with HMAC-SHA256:
  Header: creem-signature
  Signed payload: raw request body
  Secret: webhook secret from dashboard
  """

  def verify(raw_body, headers) do
    case get_header(headers, "creem-signature") do
      {:ok, signature} ->
        secret = webhook_secret()

        expected =
          :crypto.mac(:hmac, :sha256, secret, raw_body)
          |> Base.encode16(case: :lower)

        if Plug.Crypto.secure_compare(expected, signature) do
          :ok
        else
          {:error, :invalid_signature}
        end

      error ->
        error
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

  defp webhook_secret do
    config = Application.get_env(:uptrack, :creem) || %{}
    config[:webhook_secret] || raise "CREEM_WEBHOOK_SECRET not configured"
  end
end
