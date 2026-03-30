defmodule Uptrack.Emails.CustomSenders do
  @moduledoc """
  Context for managing custom email senders per organization.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Emails.{CustomSender, SenderVerification}

  def get_sender(organization_id) do
    AppRepo.get_by(CustomSender, organization_id: organization_id)
  end

  def get_verified_sender(organization_id) do
    CustomSender
    |> where([s], s.organization_id == ^organization_id and s.verified == true)
    |> AppRepo.one()
  end

  @doc """
  Returns the {name, email} tuple for sending emails.
  Uses custom sender if verified, otherwise falls back to default.
  """
  def sender_for(organization_id) do
    case get_verified_sender(organization_id) do
      %CustomSender{sender_name: name, sender_email: email} -> {name, email}
      nil -> {"Uptrack", "alerts@uptrack.app"}
    end
  end

  def setup_sender(organization_id, sender_name, sender_email) do
    token = CustomSender.generate_token()

    attrs = %{
      organization_id: organization_id,
      sender_name: sender_name,
      sender_email: sender_email,
      verified: false,
      verification_token: token
    }

    result =
      case get_sender(organization_id) do
        nil ->
          %CustomSender{}
          |> CustomSender.changeset(attrs)
          |> AppRepo.insert()

        existing ->
          existing
          |> CustomSender.changeset(attrs)
          |> AppRepo.update()
      end

    with {:ok, sender} <- result do
      SenderVerification.send_verification(sender)
      {:ok, sender}
    end
  end

  def verify_token(token) do
    case AppRepo.get_by(CustomSender, verification_token: token) do
      nil ->
        {:error, :invalid_token}

      sender ->
        sender
        |> CustomSender.changeset(%{verified: true, verification_token: nil})
        |> AppRepo.update()
    end
  end

  def delete_sender(organization_id) do
    case get_sender(organization_id) do
      nil -> {:error, :not_found}
      sender -> AppRepo.delete(sender)
    end
  end
end
