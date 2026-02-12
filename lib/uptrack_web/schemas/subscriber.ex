defmodule UptrackWeb.Schemas.Subscriber do
  @moduledoc """
  OpenAPI schemas for subscriber endpoints.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule SubscribeRequest do
    OpenApiSpex.schema(%{
      title: "SubscribeRequest",
      description: "Request to subscribe to status page updates",
      type: :object,
      required: [:email],
      properties: %{
        email: %Schema{
          type: :string,
          format: :email,
          example: "user@example.com"
        }
      }
    })
  end

  defmodule SubscribeResponse do
    OpenApiSpex.schema(%{
      title: "SubscribeResponse",
      description: "Response after subscription request",
      type: :object,
      required: [:ok, :message],
      properties: %{
        ok: %Schema{type: :boolean, example: true},
        message: %Schema{
          type: :string,
          example: "Please check your email to verify your subscription"
        }
      }
    })
  end

  defmodule VerifyResponse do
    OpenApiSpex.schema(%{
      title: "VerifyResponse",
      description: "Response after verifying subscription",
      type: :object,
      required: [:ok, :message],
      properties: %{
        ok: %Schema{type: :boolean, example: true},
        message: %Schema{
          type: :string,
          example: "Your subscription has been verified"
        }
      }
    })
  end

  defmodule UnsubscribeResponse do
    OpenApiSpex.schema(%{
      title: "UnsubscribeResponse",
      description: "Response after unsubscribing",
      type: :object,
      required: [:ok, :message],
      properties: %{
        ok: %Schema{type: :boolean, example: true},
        message: %Schema{
          type: :string,
          example: "You have been unsubscribed"
        }
      }
    })
  end

  defmodule ErrorResponse do
    OpenApiSpex.schema(%{
      title: "SubscriberErrorResponse",
      description: "Error response from subscriber endpoints",
      type: :object,
      required: [:ok, :error],
      properties: %{
        ok: %Schema{type: :boolean, example: false},
        error: %Schema{type: :string, example: "Invalid email address"}
      }
    })
  end
end
