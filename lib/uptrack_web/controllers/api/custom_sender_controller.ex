defmodule UptrackWeb.Api.CustomSenderController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Emails.CustomSenders

  def show(conn, _params) do
    org = conn.assigns.current_organization
    sender = CustomSenders.get_sender(org.id)

    json(conn, %{
      data: if(sender, do: %{
        sender_name: sender.sender_name,
        sender_email: sender.sender_email,
        verified: sender.verified
      })
    })
  end

  def create(conn, %{"sender_name" => name, "sender_email" => email}) do
    org = conn.assigns.current_organization

    if Billing.can_use_feature?(org, :custom_email_sender) do
      case CustomSenders.setup_sender(org.id, name, email) do
        {:ok, _} ->
          json(conn, %{ok: true, message: "Verification email sent to #{email}"})

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      conn
      |> put_status(402)
      |> json(%{error: %{message: "Custom email sender is available on the Business plan."}})
    end
  end

  def verify(conn, %{"token" => token}) do
    case CustomSenders.verify_token(token) do
      {:ok, _} ->
        json(conn, %{ok: true, message: "Email verified! Your custom sender is now active."})

      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{message: "Invalid or expired verification token."}})
    end
  end

  def delete(conn, _params) do
    org = conn.assigns.current_organization

    case CustomSenders.delete_sender(org.id) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, :not_found} -> json(conn, %{ok: true})
    end
  end
end
