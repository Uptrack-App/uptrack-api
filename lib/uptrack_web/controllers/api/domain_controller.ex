defmodule UptrackWeb.Api.DomainController do
  @moduledoc """
  API endpoints for custom domain management on status pages.
  """

  use UptrackWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Uptrack.{Domains, Monitoring}
  alias UptrackWeb.Schemas.Domain

  tags ["Domains"]

  operation :show,
    summary: "Get domain configuration",
    description: "Returns the custom domain configuration and DNS records needed for verification.",
    security: [%{"session" => []}],
    parameters: [
      status_page_id: [in: :path, description: "Status page ID", schema: %OpenApiSpex.Schema{type: :string}]
    ],
    responses: [
      ok: {"Domain configuration", "application/json", Domain.ConfigResponse},
      not_found: {"Status page not found", "application/json", Domain.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Domain.ErrorResponse}
    ]

  operation :update,
    summary: "Set custom domain",
    description: "Sets or updates the custom domain for a status page. Resets verification status.",
    security: [%{"session" => []}],
    parameters: [
      status_page_id: [in: :path, description: "Status page ID", schema: %OpenApiSpex.Schema{type: :string}]
    ],
    request_body: {"Domain settings", "application/json", Domain.UpdateRequest},
    responses: [
      ok: {"Domain updated", "application/json", Domain.ConfigResponse},
      unprocessable_entity: {"Validation error", "application/json", Domain.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Domain.ErrorResponse}
    ]

  operation :verify,
    summary: "Verify domain ownership",
    description: "Checks DNS records to verify domain ownership. Must have TXT and CNAME records configured.",
    security: [%{"session" => []}],
    parameters: [
      status_page_id: [in: :path, description: "Status page ID", schema: %OpenApiSpex.Schema{type: :string}]
    ],
    responses: [
      ok: {"Domain verified", "application/json", Domain.VerifyResponse},
      unprocessable_entity: {"Verification failed", "application/json", Domain.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Domain.ErrorResponse}
    ]

  operation :delete,
    summary: "Remove custom domain",
    description: "Removes the custom domain from a status page.",
    security: [%{"session" => []}],
    parameters: [
      status_page_id: [in: :path, description: "Status page ID", schema: %OpenApiSpex.Schema{type: :string}]
    ],
    responses: [
      ok: {"Domain removed", "application/json", Domain.SuccessResponse},
      not_found: {"Status page not found", "application/json", Domain.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Domain.ErrorResponse}
    ]

  @doc """
  GET /api/status-pages/:status_page_id/domain

  Returns the domain configuration and required DNS records.
  """
  def show(conn, %{"status_page_id" => status_page_id}) do
    %{current_organization: org} = conn.assigns

    case get_status_page(org.id, status_page_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      status_page ->
        dns_records = if status_page.custom_domain do
          Domains.get_verification_records(status_page)
        else
          nil
        end

        json(conn, %{
          custom_domain: status_page.custom_domain,
          domain_verified: status_page.domain_verified,
          domain_verified_at: status_page.domain_verified_at,
          domain_verification_token: status_page.domain_verification_token,
          ssl_status: status_page.ssl_status,
          ssl_expires_at: status_page.ssl_expires_at,
          dns_records: dns_records
        })
    end
  end

  @doc """
  PUT /api/status-pages/:status_page_id/domain

  Sets or updates the custom domain.
  """
  def update(conn, %{"status_page_id" => status_page_id} = params) do
    %{current_organization: org} = conn.assigns
    custom_domain = params["custom_domain"] || params["domain"]

    case get_status_page(org.id, status_page_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      status_page ->
        case Monitoring.update_status_page(status_page, %{custom_domain: custom_domain}) do
          {:ok, updated} ->
            dns_records = if updated.custom_domain do
              Domains.get_verification_records(updated)
            else
              nil
            end

            json(conn, %{
              custom_domain: updated.custom_domain,
              domain_verified: updated.domain_verified,
              domain_verification_token: updated.domain_verification_token,
              ssl_status: updated.ssl_status,
              dns_records: dns_records
            })

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Validation failed", details: errors})
        end
    end
  end

  @doc """
  POST /api/status-pages/:status_page_id/domain/verify

  Triggers domain verification via DNS lookup.
  """
  def verify(conn, %{"status_page_id" => status_page_id}) do
    %{current_organization: org} = conn.assigns

    case get_status_page(org.id, status_page_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      %{custom_domain: nil} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No custom domain configured"})

      %{domain_verified: true} = status_page ->
        json(conn, %{
          verified: true,
          domain: status_page.custom_domain,
          verified_at: status_page.domain_verified_at,
          message: "Domain is already verified"
        })

      status_page ->
        case Domains.verify_domain(status_page) do
          {:ok, updated} ->
            json(conn, %{
              verified: true,
              domain: updated.custom_domain,
              verified_at: updated.domain_verified_at,
              message: "Domain verified successfully"
            })

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              verified: false,
              error: reason,
              dns_records: Domains.get_verification_records(status_page)
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{verified: false, error: inspect(reason)})
        end
    end
  end

  @doc """
  DELETE /api/status-pages/:status_page_id/domain

  Removes the custom domain from a status page.
  """
  def delete(conn, %{"status_page_id" => status_page_id}) do
    %{current_organization: org} = conn.assigns

    case get_status_page(org.id, status_page_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Status page not found"})

      status_page ->
        case Monitoring.update_status_page(status_page, %{custom_domain: nil}) do
          {:ok, _} ->
            json(conn, %{success: true, message: "Custom domain removed"})

          {:error, _changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to remove domain"})
        end
    end
  end

  # Private helpers

  defp get_status_page(organization_id, status_page_id) do
    Monitoring.get_organization_status_page(organization_id, status_page_id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
