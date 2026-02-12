defmodule Uptrack.Domains do
  @moduledoc """
  Context for managing custom domains for status pages.

  Handles domain verification via DNS TXT records and SSL certificate status tracking.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Uptrack.Monitoring.StatusPage
  require Logger

  @verification_prefix "_uptrack-verification"
  @uptrack_cname "status.uptrack.dev"

  @doc """
  Returns the DNS records needed for domain verification.

  ## Example

      iex> get_verification_records(%StatusPage{custom_domain: "status.example.com", domain_verification_token: "abc123"})
      %{
        txt_record: %{
          name: "_uptrack-verification.status.example.com",
          type: "TXT",
          value: "abc123"
        },
        cname_record: %{
          name: "status.example.com",
          type: "CNAME",
          value: "status.uptrack.dev"
        }
      }
  """
  def get_verification_records(%StatusPage{} = status_page) do
    domain = status_page.custom_domain
    token = status_page.domain_verification_token

    %{
      txt_record: %{
        name: "#{@verification_prefix}.#{domain}",
        type: "TXT",
        value: token
      },
      cname_record: %{
        name: domain,
        type: "CNAME",
        value: @uptrack_cname
      }
    }
  end

  @doc """
  Verifies a custom domain by checking DNS records.

  Checks for:
  1. TXT record with verification token
  2. CNAME pointing to Uptrack

  Returns {:ok, status_page} if verified, {:error, reason} otherwise.
  """
  def verify_domain(%StatusPage{} = status_page) do
    domain = status_page.custom_domain
    token = status_page.domain_verification_token

    if is_nil(domain) or domain == "" do
      {:error, :no_domain_configured}
    else
      with {:ok, :txt_verified} <- verify_txt_record(domain, token),
           {:ok, :cname_verified} <- verify_cname_record(domain) do
        # Update the status page as verified
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        status_page
        |> StatusPage.domain_verification_changeset(%{
          domain_verified: true,
          domain_verified_at: now
        })
        |> AppRepo.update()
      else
        {:error, :txt_not_found} ->
          {:error, "TXT record not found. Add #{@verification_prefix}.#{domain} with value: #{token}"}

        {:error, :txt_mismatch} ->
          {:error, "TXT record found but token doesn't match"}

        {:error, :cname_not_found} ->
          {:error, "CNAME record not found. Point #{domain} to #{@uptrack_cname}"}

        {:error, :cname_mismatch} ->
          {:error, "CNAME record found but doesn't point to #{@uptrack_cname}"}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Looks up a status page by its custom domain.
  """
  def get_status_page_by_domain(domain) when is_binary(domain) do
    domain = String.downcase(domain)

    StatusPage
    |> where([sp], sp.custom_domain == ^domain and sp.domain_verified == true)
    |> AppRepo.one()
  end

  @doc """
  Updates the SSL certificate status for a status page.
  """
  def update_ssl_status(%StatusPage{} = status_page, status, opts \\ []) do
    attrs = %{ssl_status: status}

    attrs =
      case status do
        "active" ->
          Map.merge(attrs, %{
            ssl_issued_at: Keyword.get(opts, :issued_at, DateTime.utc_now()),
            ssl_expires_at: Keyword.get(opts, :expires_at)
          })

        _ ->
          attrs
      end

    status_page
    |> StatusPage.ssl_changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Lists all status pages with custom domains that need SSL renewal.
  SSL certificates are renewed when they expire within 30 days.
  """
  def list_domains_needing_renewal do
    threshold = DateTime.utc_now() |> DateTime.add(30, :day)

    StatusPage
    |> where([sp], not is_nil(sp.custom_domain))
    |> where([sp], sp.domain_verified == true)
    |> where([sp], sp.ssl_status == "active")
    |> where([sp], sp.ssl_expires_at < ^threshold)
    |> AppRepo.all()
  end

  @doc """
  Lists all verified custom domains for Caddy/nginx configuration.
  """
  def list_verified_domains do
    StatusPage
    |> where([sp], not is_nil(sp.custom_domain))
    |> where([sp], sp.domain_verified == true)
    |> select([sp], %{
      domain: sp.custom_domain,
      status_page_id: sp.id,
      slug: sp.slug,
      ssl_status: sp.ssl_status
    })
    |> AppRepo.all()
  end

  # Private DNS verification functions

  defp verify_txt_record(domain, expected_token) do
    txt_name = "#{@verification_prefix}.#{domain}"

    case :inet_res.lookup(to_charlist(txt_name), :in, :txt) do
      [] ->
        {:error, :txt_not_found}

      records ->
        # TXT records come back as lists of charlists
        found =
          Enum.any?(records, fn record_parts ->
            record_value = record_parts |> Enum.map(&to_string/1) |> Enum.join()
            record_value == expected_token
          end)

        if found do
          {:ok, :txt_verified}
        else
          {:error, :txt_mismatch}
        end
    end
  rescue
    e ->
      Logger.error("DNS lookup failed for #{domain}: #{inspect(e)}")
      {:error, :dns_lookup_failed}
  end

  defp verify_cname_record(domain) do
    case :inet_res.lookup(to_charlist(domain), :in, :cname) do
      [] ->
        # CNAME not found, but domain might be an A record pointing correctly
        # In production, you might also check A/AAAA records
        {:error, :cname_not_found}

      [cname | _] ->
        cname_value = to_string(cname) |> String.trim_trailing(".")

        if cname_value == @uptrack_cname or String.ends_with?(cname_value, ".#{@uptrack_cname}") do
          {:ok, :cname_verified}
        else
          {:error, :cname_mismatch}
        end
    end
  rescue
    e ->
      Logger.error("CNAME lookup failed for #{domain}: #{inspect(e)}")
      {:error, :dns_lookup_failed}
  end
end
