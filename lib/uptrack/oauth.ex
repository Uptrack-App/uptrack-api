defmodule Uptrack.OAuth do
  @moduledoc """
  OAuth 2.0 context for managing OAuth clients.

  Public API for creating, listing, and revoking OAuth clients
  used by third-party integrations (Claude.ai, custom apps).
  """

  import Bitwise
  import Ecto.Query

  alias Boruta.Ecto.Admin
  alias Uptrack.AppRepo

  # Private IP ranges blocked for SSRF protection (RFC1918 + loopback + link-local)
  @private_ip_ranges [
    {{10, 0, 0, 0}, 8},
    {{172, 16, 0, 0}, 12},
    {{192, 168, 0, 0}, 16},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    # IPv6 loopback ::1
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    # IPv6 unique local fc00::/7
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7}
  ]

  @metadata_fetch_timeout 3_000

  @doc """
  Resolves a client_id to its name and allowed redirect_uris.

  Dispatches on client_id format:
  - HTTPS URL → fetch Client ID Metadata Document
  - plain string → Boruta DB lookup
  """
  def resolve_client("https://" <> _ = client_id), do: fetch_client_metadata(client_id)

  def resolve_client(client_id) when is_binary(client_id) do
    case get_client(client_id) do
      {:ok, client} ->
        {:ok, %{name: client.name, redirect_uris: client.redirect_uris, source: :registered}}

      {:error, :not_found} ->
        {:error, :client_not_found}
    end
  end

  @doc """
  Fetches and validates a Client ID Metadata Document from an HTTPS URL.

  SSRF protection:
  - Only HTTPS URLs allowed
  - Private/loopback IP ranges rejected
  - 3-second timeout
  - client_id field in document must match URL exactly
  """
  def fetch_client_metadata(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- validate_metadata_url(uri),
         {:ok, ip} <- resolve_host(uri.host),
         :ok <- validate_not_private_ip(ip),
         {:ok, body} <- do_fetch(url),
         :ok <- validate_client_id_field(body, url) do
      redirect_uris = Map.get(body, "redirect_uris", [])
      client_name = Map.get(body, "client_name", uri.host)
      {:ok, %{name: client_name, redirect_uris: redirect_uris, source: :metadata_doc}}
    end
  end

  defp validate_metadata_url(%URI{scheme: "https", host: host}) when is_binary(host) and host != "",
    do: :ok

  defp validate_metadata_url(_), do: {:error, :invalid_client}

  defp resolve_host(host) do
    case :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} ->
        case :inet.getaddr(String.to_charlist(host), :inet6) do
          {:ok, ip} -> {:ok, ip}
          {:error, _} -> {:error, :invalid_client}
        end
    end
  end

  defp validate_not_private_ip(ip) do
    if private_ip?(ip), do: {:error, :invalid_client}, else: :ok
  end

  defp do_fetch(url) do
    task = Task.async(fn ->
      Req.get(url,
        receive_timeout: @metadata_fetch_timeout,
        connect_options: [timeout: @metadata_fetch_timeout]
      )
    end)

    case Task.await(task, @metadata_fetch_timeout + 1_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> {:error, :invalid_client}
        end
      _ -> {:error, :invalid_client}
    end
  rescue
    _ -> {:error, :invalid_client}
  catch
    :exit, _ -> {:error, :invalid_client}
  end

  defp validate_client_id_field(body, url) do
    if Map.get(body, "client_id") == url, do: :ok, else: {:error, :invalid_client}
  end

  defp private_ip?(ip) when is_tuple(ip) do
    Enum.any?(@private_ip_ranges, fn {range, prefix_len} ->
      ip_in_range?(ip, range, prefix_len)
    end)
  end

  defp ip_in_range?(ip, range, prefix_len) when tuple_size(ip) == 4 and tuple_size(range) == 4 do
    ip_int = ip_to_int32(ip)
    range_int = ip_to_int32(range)
    mask = bnot(bsr(0xFFFFFFFF, prefix_len) - 1) &&& 0xFFFFFFFF
    (ip_int &&& mask) == (range_int &&& mask)
  rescue
    _ -> false
  end

  defp ip_in_range?(ip, range, prefix_len) when tuple_size(ip) == 8 and tuple_size(range) == 8 do
    ip_int = ip_to_int128(ip)
    range_int = ip_to_int128(range)
    full_mask = (1 <<< 128) - 1
    mask = bnot(bsr(full_mask, prefix_len)) &&& full_mask
    (ip_int &&& mask) == (range_int &&& mask)
  rescue
    _ -> false
  end

  defp ip_in_range?(_, _, _), do: false

  defp ip_to_int32({a, b, c, d}), do: a * 0x1000000 + b * 0x10000 + c * 0x100 + d

  defp ip_to_int128({a, b, c, d, e, f, g, h}) do
    a * (1 <<< 112) + b * (1 <<< 96) + c * (1 <<< 80) + d * (1 <<< 64) +
    e * (1 <<< 48) + f * (1 <<< 32) + g * (1 <<< 16) + h
  end

  @doc "Lists OAuth clients for an organization."
  def list_clients(organization_id) do
    from(c in "oauth_clients",
      where: fragment("?->>'organization_id' = ?", c.metadata, ^organization_id),
      select: %{
        id: type(c.id, :string),
        name: c.name,
        redirect_uris: c.redirect_uris,
        inserted_at: c.inserted_at
      }
    )
    |> AppRepo.all()
  end

  @doc "Creates a new OAuth client for an organization (confidential, with org binding)."
  def create_client(attrs) do
    client_attrs = %{
      name: attrs["name"],
      redirect_uris: List.wrap(attrs["redirect_uris"]),
      supported_grant_types: ["authorization_code", "refresh_token"],
      confidential: true,
      pkce: true,
      metadata: %{"organization_id" => attrs["organization_id"]}
    }

    Admin.create_client(client_attrs)
  end

  @doc "Creates a dynamic (public) OAuth client via RFC7591 registration."
  def create_dynamic_client(attrs) do
    client_attrs = %{
      name: Map.get(attrs, "client_name", "Unnamed Client"),
      redirect_uris: List.wrap(Map.get(attrs, "redirect_uris", [])),
      supported_grant_types: normalize_grant_types(Map.get(attrs, "grant_types", ["authorization_code"])),
      confidential: false,
      pkce: true,
      access_token_ttl: 3600,
      refresh_token_ttl: 2_592_000
    }

    Admin.create_client(client_attrs)
  end

  defp normalize_grant_types(types) when is_list(types) do
    allowed = ~w(authorization_code refresh_token)
    Enum.filter(types, &(&1 in allowed))
  end

  defp normalize_grant_types(_), do: ["authorization_code"]

  @doc "Deletes an OAuth client by ID."
  def delete_client(client_id) do
    client = Admin.get_client!(client_id)
    Admin.delete_client(client)
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  @doc "Gets an OAuth client by ID."
  def get_client(client_id) do
    {:ok, Admin.get_client!(client_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
