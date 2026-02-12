defmodule UptrackWeb.Api.SubscriberController do
  use UptrackWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{StatusPage, StatusPageSubscriber}
  alias Uptrack.Mailer
  alias Uptrack.Emails.SubscriberEmail
  alias UptrackWeb.Schemas.Subscriber, as: SubscriberSchemas

  tags ["Subscriptions"]

  operation :subscribe,
    summary: "Subscribe to status page",
    description: "Subscribe an email address to receive notifications about status page incidents.",
    parameters: [
      slug: [
        in: :path,
        type: :string,
        required: true,
        description: "Status page slug"
      ]
    ],
    request_body: {"Subscription request", "application/json", SubscriberSchemas.SubscribeRequest},
    responses: [
      created: {"Subscription created", "application/json", SubscriberSchemas.SubscribeResponse},
      ok: {"Already subscribed", "application/json", SubscriberSchemas.SubscribeResponse},
      not_found: {"Status page not found", "application/json", SubscriberSchemas.ErrorResponse},
      forbidden: {"Subscriptions disabled", "application/json", SubscriberSchemas.ErrorResponse}
    ]

  @doc """
  Subscribe to a status page.
  POST /api/status/:slug/subscribe
  """
  def subscribe(conn, %{"slug" => slug, "email" => email}) do
    with {:ok, status_page} <- get_subscribable_status_page(slug),
         false <- Monitoring.subscriber_exists?(status_page.id, email),
         {:ok, subscriber} <- Monitoring.subscribe_to_status_page(status_page.id, email) do
      # Send verification email
      send_verification_email(subscriber, status_page)

      conn
      |> put_status(:created)
      |> json(%{
        success: true,
        message: "Please check your email to verify your subscription."
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      {:error, :subscriptions_disabled} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Subscriptions are not enabled for this status page"})

      true ->
        # Already subscribed
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: "You're already subscribed. Check your email for the verification link."
        })

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: errors})
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email is required"})
  end

  operation :verify,
    summary: "Verify email subscription",
    description: "Verify an email subscription using the token sent via email.",
    parameters: [
      token: [
        in: :path,
        type: :string,
        required: true,
        description: "Verification token from email"
      ]
    ],
    responses: [
      ok: {"Email verified", "application/json", SubscriberSchemas.VerifyResponse},
      not_found: {"Invalid token", "application/json", SubscriberSchemas.ErrorResponse}
    ]

  @doc """
  Verify email subscription.
  GET /api/subscribe/verify/:token
  """
  def verify(conn, %{"token" => token}) do
    case Monitoring.get_subscriber_by_verification_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired verification token"})

      %StatusPageSubscriber{verified: true} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true, message: "Email already verified"})

      subscriber ->
        case Monitoring.verify_subscriber(subscriber) do
          {:ok, _subscriber} ->
            conn
            |> put_status(:ok)
            |> json(%{success: true, message: "Email verified successfully. You'll now receive incident notifications."})

          {:error, _changeset} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to verify subscription"})
        end
    end
  end

  operation :unsubscribe,
    summary: "Unsubscribe from notifications",
    description: "Unsubscribe an email from status page notifications.",
    parameters: [
      token: [
        in: :path,
        type: :string,
        required: true,
        description: "Unsubscribe token from email footer"
      ]
    ],
    responses: [
      ok: {"Unsubscribed", "application/json", SubscriberSchemas.UnsubscribeResponse},
      not_found: {"Invalid token", "application/json", SubscriberSchemas.ErrorResponse}
    ]

  @doc """
  Unsubscribe from notifications.
  GET /api/subscribe/unsubscribe/:token
  """
  def unsubscribe(conn, %{"token" => token}) do
    case Monitoring.get_subscriber_by_unsubscribe_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid unsubscribe token"})

      subscriber ->
        case Monitoring.unsubscribe(subscriber) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{success: true, message: "Successfully unsubscribed"})

          {:error, _} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to unsubscribe"})
        end
    end
  end

  # Private functions

  defp get_subscribable_status_page(slug) do
    case Monitoring.get_status_page_by_slug(slug) do
      nil ->
        {:error, :not_found}

      %StatusPage{allow_subscriptions: false} ->
        {:error, :subscriptions_disabled}

      status_page ->
        {:ok, status_page}
    end
  end

  defp send_verification_email(subscriber, status_page) do
    subscriber
    |> SubscriberEmail.verification_email(status_page)
    |> Mailer.deliver()
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
