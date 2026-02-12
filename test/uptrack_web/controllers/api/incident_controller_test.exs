defmodule UptrackWeb.Api.IncidentControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Monitoring

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/incidents" do
    test "lists incidents for the organization", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, _incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Timeout"
        })

      conn = get(conn, "/api/incidents")

      response = json_response(conn, 200)
      assert [incident] = response["data"]
      assert incident["cause"] == "Timeout"
      assert incident["status"] == "ongoing"
    end

    test "filters ongoing incidents", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Error"
        })

      {:ok, _resolved} = Monitoring.resolve_incident(incident)

      conn = get(conn, "/api/incidents", %{"status" => "ongoing"})

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "does not return incidents from other orgs", %{conn: conn} do
      {other_user, other_org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: other_org.id, user_id: other_user.id)

      {:ok, _} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: other_org.id,
          cause: "Error"
        })

      conn = get(conn, "/api/incidents")

      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "GET /api/incidents/:id" do
    test "returns a specific incident", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Down"
        })

      conn = get(conn, "/api/incidents/#{incident.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == incident.id
      assert response["data"]["monitor_name"]
    end

    test "returns 404 for other org's incident", %{conn: conn} do
      {other_user, other_org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: other_org.id, user_id: other_user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: other_org.id,
          cause: "Error"
        })

      conn = get(conn, "/api/incidents/#{incident.id}")

      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent incident", %{conn: conn} do
      conn = get(conn, "/api/incidents/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/incidents" do
    test "creates an incident for a monitor", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn =
        post(conn, "/api/incidents", %{
          "monitor_id" => monitor.id,
          "cause" => "Server timeout"
        })

      response = json_response(conn, 201)
      assert response["data"]["status"] == "ongoing"
      assert response["data"]["cause"] == "Server timeout"
      assert response["data"]["monitor_name"] == monitor.name
    end

    test "creates an incident without a cause", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      conn = post(conn, "/api/incidents", %{"monitor_id" => monitor.id})

      response = json_response(conn, 201)
      assert response["data"]["status"] == "ongoing"
    end

    test "returns 404 for monitor in different org", %{conn: conn} do
      other_monitor = monitor_fixture()

      conn = post(conn, "/api/incidents", %{"monitor_id" => other_monitor.id})

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/incidents/:id" do
    test "resolves an ongoing incident", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Outage"
        })

      conn = patch(conn, "/api/incidents/#{incident.id}", %{"status" => "resolved"})

      response = json_response(conn, 200)
      assert response["data"]["status"] == "resolved"
      assert response["data"]["resolved_at"] != nil
    end

    test "updates cause on an incident", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Unknown"
        })

      conn = patch(conn, "/api/incidents/#{incident.id}", %{"cause" => "DNS failure"})

      response = json_response(conn, 200)
      assert response["data"]["cause"] == "DNS failure"
    end

    test "returns 404 for other org's incident", %{conn: conn} do
      {other_user, other_org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: other_org.id, user_id: other_user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: other_org.id,
          cause: "Error"
        })

      conn = patch(conn, "/api/incidents/#{incident.id}", %{"status" => "resolved"})

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/incidents/:incident_id/updates" do
    test "posts a status update to an incident", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Outage"
        })

      conn =
        post(conn, "/api/incidents/#{incident.id}/updates", %{
          "title" => "Investigating root cause",
          "description" => "Looking into the issue",
          "status" => "investigating"
        })

      response = json_response(conn, 200)
      assert [update | _] = response["data"]["updates"]
      assert update["title"] == "Investigating root cause"
      assert update["status"] == "investigating"
    end

    test "posting a resolved update auto-resolves the incident", %{conn: conn, user: user, org: org} do
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Outage"
        })

      conn =
        post(conn, "/api/incidents/#{incident.id}/updates", %{
          "title" => "Issue fixed",
          "description" => "Deployed hotfix",
          "status" => "resolved"
        })

      response = json_response(conn, 200)
      assert response["data"]["status"] == "resolved"
      assert response["data"]["resolved_at"] != nil
    end

    test "returns 404 for other org's incident", %{conn: conn} do
      {other_user, other_org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: other_org.id, user_id: other_user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: other_org.id,
          cause: "Error"
        })

      conn =
        post(conn, "/api/incidents/#{incident.id}/updates", %{
          "title" => "Test",
          "description" => "Test",
          "status" => "investigating"
        })

      assert json_response(conn, 404)
    end
  end
end
