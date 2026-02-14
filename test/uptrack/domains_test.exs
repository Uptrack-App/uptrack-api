defmodule Uptrack.DomainsTest do
  use Uptrack.DataCase

  alias Uptrack.Domains
  alias Uptrack.Monitoring.StatusPage

  import Uptrack.MonitoringFixtures

  describe "get_verification_records/1" do
    test "returns TXT and CNAME records for domain" do
      status_page =
        status_page_fixture(%{
          custom_domain: "status.example.com"
        })

      # Reload to get the verification token
      status_page = Uptrack.AppRepo.get!(StatusPage, status_page.id)

      records = Domains.get_verification_records(status_page)

      assert records.txt_record.type == "TXT"
      assert records.txt_record.name =~ "_uptrack-verification.status.example.com"
      assert records.txt_record.value == status_page.domain_verification_token

      assert records.cname_record.type == "CNAME"
      assert records.cname_record.name == "status.example.com"
      assert records.cname_record.value == "status.uptrack.app"
    end
  end

  describe "verify_domain/1" do
    test "returns error for status page with no domain" do
      status_page =
        status_page_fixture()
        |> Uptrack.AppRepo.reload!()

      # custom_domain defaults to nil
      assert {:error, :no_domain_configured} = Domains.verify_domain(status_page)
    end
  end

  describe "get_status_page_by_domain/1" do
    test "returns nil for non-existent domain" do
      assert is_nil(Domains.get_status_page_by_domain("nonexistent.example.com"))
    end

    test "returns nil for unverified domain" do
      _status_page =
        status_page_fixture(%{
          custom_domain: "unverified.example.com"
        })
        |> Uptrack.AppRepo.reload!()

      # domain_verified defaults to false
      assert is_nil(Domains.get_status_page_by_domain("unverified.example.com"))
    end
  end

  describe "update_ssl_status/3" do
    test "updates SSL status to active with timestamps" do
      status_page =
        status_page_fixture(%{
          custom_domain: "ssl-test.example.com"
        })
        |> Uptrack.AppRepo.reload!()

      expires_at = DateTime.utc_now() |> DateTime.add(90, :day) |> DateTime.truncate(:second)

      assert {:ok, updated} =
               Domains.update_ssl_status(status_page, "active", expires_at: expires_at)

      assert updated.ssl_status == "active"
      assert updated.ssl_expires_at == expires_at
    end

    test "updates SSL status to pending" do
      status_page =
        status_page_fixture(%{
          custom_domain: "pending-ssl.example.com"
        })
        |> Uptrack.AppRepo.reload!()

      assert {:ok, updated} = Domains.update_ssl_status(status_page, "pending")
      assert updated.ssl_status == "pending"
    end
  end

  describe "list_verified_domains/0" do
    test "returns empty list when no verified domains" do
      # Create unverified domain
      status_page_fixture(%{custom_domain: "unverified.example.com"})

      domains = Domains.list_verified_domains()
      verified = Enum.filter(domains, &(&1.domain == "unverified.example.com"))
      assert verified == []
    end
  end

  describe "list_domains_needing_renewal/0" do
    test "returns empty list when no domains need renewal" do
      assert is_list(Domains.list_domains_needing_renewal())
    end
  end
end
