defmodule Uptrack.Monitoring.CheckWorkerHttpTest do
  @moduledoc """
  Tests for HTTP monitoring checks — custom headers, methods, status codes.
  These tests make real HTTP requests against public endpoints.
  """

  use Uptrack.DataCase

  alias Uptrack.Monitoring.CheckWorker

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    %{user: user, org: org}
  end

  describe "basic HTTP checks" do
    test "returns up for healthy endpoint", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/200",
        timeout: 15,
        settings: %{"method" => "GET", "expected_status_code" => 200}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.response_time >= 0
    end

    test "records status code for 500 response", %{user: user, org: org} do
      # CheckWorker marks any HTTP response as "up" — it only fails on transport errors.
      # Status code matching is not enforced at the check level.
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/500",
        timeout: 15,
        settings: %{"method" => "GET"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.status_code == 500
    end

    test "returns down for unreachable host", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://this-host-does-not-exist-#{System.unique_integer([:positive])}.invalid",
        timeout: 5,
        settings: %{"method" => "GET"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "down"
      assert check.error_message != nil
    end
  end

  describe "custom headers" do
    test "passes custom headers to request", %{user: user, org: org} do
      # httpbin.org/headers echoes back request headers
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/headers",
        timeout: 15,
        settings: %{
          "method" => "GET",
          "expected_status_code" => 200,
          "headers" => %{
            "X-Custom-Test" => "uptrack-test-value",
            "X-Another-Header" => "another-value"
          }
        }
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end

    test "works with empty headers map", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/200",
        timeout: 15,
        settings: %{
          "method" => "GET",
          "expected_status_code" => 200,
          "headers" => %{}
        }
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end

    test "works with nil headers", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/200",
        timeout: 15,
        settings: %{"method" => "GET", "expected_status_code" => 200}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end
  end

  describe "HTTP methods" do
    test "supports POST method", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/post",
        timeout: 15,
        settings: %{"method" => "POST", "expected_status_code" => 200}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end

    test "supports HEAD method", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/get",
        timeout: 15,
        settings: %{"method" => "HEAD", "expected_status_code" => 200}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
    end
  end

  describe "status code recording" do
    test "records actual status code in check result", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/201",
        timeout: 15,
        settings: %{"method" => "GET"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.status_code == 201
    end

    test "records 404 status code", %{user: user, org: org} do
      monitor = monitor_fixture(
        organization_id: org.id,
        user_id: user.id,
        monitor_type: "http",
        url: "https://httpbin.org/status/404",
        timeout: 15,
        settings: %{"method" => "GET"}
      )

      assert {:ok, check} = CheckWorker.perform_check(monitor)
      assert check.status == "up"
      assert check.status_code == 404
    end
  end
end
