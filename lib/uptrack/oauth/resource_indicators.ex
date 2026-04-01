defmodule Uptrack.OAuth.ResourceIndicators do
  @moduledoc """
  RFC 8707 Resource Indicators for MCP compliance.

  Validates and formats the `resource` parameter on token requests
  to bind tokens to the Uptrack API.
  """

  @doc "Returns the server's canonical resource URI."
  @spec canonical_uri() :: String.t()
  def canonical_uri do
    host =
      Application.get_env(:uptrack, UptrackWeb.Endpoint)[:url][:host] ||
        "api.uptrack.app"

    "https://#{host}"
  end

  @spec valid_resource?(String.t() | nil) :: boolean()
  def valid_resource?(nil), do: true
  def valid_resource?(""), do: true

  def valid_resource?(resource) when is_binary(resource) do
    String.trim_trailing(resource, "/") == canonical_uri()
  end

  @spec format_resource(String.t() | nil) :: String.t()
  def format_resource(nil), do: canonical_uri()
  def format_resource(""), do: canonical_uri()
  def format_resource(resource), do: String.trim_trailing(resource, "/")

  @spec valid_audience?(String.t() | nil) :: boolean()
  def valid_audience?(nil), do: true
  def valid_audience?(""), do: true

  def valid_audience?(audience) when is_binary(audience) do
    String.trim_trailing(audience, "/") == canonical_uri()
  end

  def invalid_target_error do
    %{error: "invalid_target", error_description: "The requested resource is invalid or unknown"}
  end
end
