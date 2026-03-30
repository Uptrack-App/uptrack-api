defmodule Uptrack.Auth.SamlResponse do
  @moduledoc """
  Pure module — extracts user attributes from a Samly assertion.
  No database calls, no side effects.
  """

  @doc """
  Extracts user attributes from a Samly assertion struct.

  Returns `%{email: string, name: string | nil, provider_id: string}`.
  """
  def extract_attributes(%Samly.Assertion{} = assertion) do
    attrs = assertion.attributes

    email =
      Map.get(attrs, "email") ||
        Map.get(attrs, "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress") ||
        Map.get(attrs, "urn:oid:0.9.2342.19200300.100.1.3") ||
        assertion.subject.name

    name =
      Map.get(attrs, "displayName") ||
        Map.get(attrs, "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name") ||
        Map.get(attrs, "urn:oid:2.16.840.1.113730.3.1.241") ||
        build_name(attrs)

    %{
      email: normalize_email(email),
      name: name,
      provider_id: assertion.subject.name
    }
  end

  defp build_name(attrs) do
    first = Map.get(attrs, "firstName") || Map.get(attrs, "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname")
    last = Map.get(attrs, "lastName") || Map.get(attrs, "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname")

    case {first, last} do
      {nil, nil} -> nil
      {f, nil} -> f
      {nil, l} -> l
      {f, l} -> "#{f} #{l}"
    end
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(email) when is_binary(email), do: String.downcase(String.trim(email))
  defp normalize_email(email) when is_list(email), do: email |> List.first() |> normalize_email()
end
