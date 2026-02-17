defmodule Uptrack.Monitoring.CheckWorkerDnsSslTest do
  @moduledoc """
  Integration tests for DNS and SSL monitoring checks.
  These tests perform real DNS lookups and SSL connections.
  """

  use Uptrack.DataCase

  alias Uptrack.Monitoring.CheckWorker

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    %{user: user, org: org}
  end

  describe "DNS checks" do
    test "resolves A record for valid domain", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "dns",
        url: "google.com",
        timeout: 10,
        settings: %{"dns_record_type" => "A"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.response_time >= 0
    end

    test "returns NXDOMAIN for non-existent domain", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "dns",
        url: "this-domain-does-not-exist-#{System.unique_integer([:positive])}.invalid",
        timeout: 10,
        settings: %{"dns_record_type" => "A"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "down"
      assert check.error_message =~ "NXDOMAIN" or check.error_message =~ "not found" or check.error_message =~ "failed"
    end

    test "fails on expected value mismatch", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "dns",
        url: "google.com",
        timeout: 10,
        settings: %{
          "dns_record_type" => "A",
          "dns_expected_value" => "1.2.3.4"
        }
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "down"
      assert check.error_message =~ "mismatch"
    end

    test "succeeds when expected value matches", %{user: user, org: org} do
      # First resolve to get the actual IP
      {:ok, msg} = :inet_res.resolve(~c"one.one.one.one", :in, :a, [])
      answers = :inet_dns.msg(msg, :anlist)
      ip = answers |> hd() |> :inet_dns.rr(:data) |> Tuple.to_list() |> Enum.join(".")

      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "dns",
        url: "one.one.one.one",
        timeout: 10,
        settings: %{
          "dns_record_type" => "A",
          "dns_expected_value" => ip
        }
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end

    test "resolves NS records", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "dns",
        url: "google.com",
        timeout: 10,
        settings: %{"dns_record_type" => "NS"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end
  end

  describe "SSL checks" do
    test "checks valid SSL certificate", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "ssl",
        url: "https://google.com",
        timeout: 15,
        settings: %{"expiry_threshold" => 7}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.response_headers["ssl_subject"]
      assert check.response_headers["ssl_issuer"]
      assert check.response_headers["ssl_days_remaining"]
      assert check.response_headers["ssl_days_remaining"] > 0
    end

    test "fails with unreachable SSL host", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "ssl",
        url: "https://localhost",
        timeout: 5,
        settings: %{"expiry_threshold" => 30}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "down"
      assert check.error_message =~ "SSL" or check.error_message =~ "connection"
    end

    test "reports certificate close to expiry as down when threshold is very high", %{user: user, org: org} do
      # Set a very high threshold (9999 days) so ANY valid cert will be "expiring soon"
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "ssl",
        url: "https://google.com",
        timeout: 15,
        settings: %{"expiry_threshold" => 9999}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "down"
      assert check.error_message =~ "expires in"
    end
  end
end
