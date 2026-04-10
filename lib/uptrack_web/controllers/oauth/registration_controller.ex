defmodule UptrackWeb.OAuth.RegistrationController do
  @moduledoc """
  Dynamic Client Registration per RFC7591.

  POST /oauth/register — open endpoint, rate-limited to 10 req/IP/hour.
  Creates a public (confidential: false) OAuth client.
  """

  use UptrackWeb, :controller

  alias Uptrack.OAuth

  def register(conn, params) do
    with :ok <- validate_params(params),
         {:ok, client} <- OAuth.create_dynamic_client(params) do
      issued_at = DateTime.utc_now() |> DateTime.to_unix()

      conn
      |> put_status(:created)
      |> json(%{
        client_id: client.id,
        client_name: client.name,
        redirect_uris: client.redirect_uris,
        grant_types: client.supported_grant_types,
        response_types: ["code"],
        token_endpoint_auth_method: "none",
        client_id_issued_at: issued_at
      })
    else
      {:error, :invalid_redirect_uri} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_redirect_uri", error_description: "Redirect URIs must use HTTPS (localhost is allowed)"})

      {:error, :missing_redirect_uris} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_client_metadata", error_description: "redirect_uris is required"})

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_client_metadata", error_description: format_changeset_errors(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_client_metadata", error_description: inspect(reason)})
    end
  end

  defp validate_params(params) do
    redirect_uris = Map.get(params, "redirect_uris")

    cond do
      is_nil(redirect_uris) or redirect_uris == [] ->
        {:error, :missing_redirect_uris}

      not Enum.all?(List.wrap(redirect_uris), &valid_redirect_uri?/1) ->
        {:error, :invalid_redirect_uri}

      true ->
        :ok
    end
  end

  defp valid_redirect_uri?("https://" <> _), do: true
  defp valid_redirect_uri?("http://localhost" <> _), do: true
  defp valid_redirect_uri?("http://127.0.0.1" <> _), do: true
  defp valid_redirect_uri?(_), do: false

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
