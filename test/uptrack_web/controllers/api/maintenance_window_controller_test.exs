defmodule UptrackWeb.Api.MaintenanceWindowControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Maintenance

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    monitor = monitor_fixture(organization_id: org.id, user_id: user.id)
    {:ok, conn: conn, user: user, org: org, monitor: monitor}
  end

  defp future_window_params(opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    start_time = Keyword.get(opts, :start_time, DateTime.add(now, 3600, :second))
    end_time = Keyword.get(opts, :end_time, DateTime.add(now, 7200, :second))

    %{
      "title" => Keyword.get(opts, :title, "Scheduled Maintenance"),
      "description" => Keyword.get(opts, :description, "Upgrading database"),
      "start_time" => DateTime.to_iso8601(start_time),
      "end_time" => DateTime.to_iso8601(end_time)
    }
    |> then(fn p ->
      case Keyword.get(opts, :monitor_id) do
        nil -> p
        id -> Map.put(p, "monitor_id", id)
      end
    end)
  end

  defp create_window(org_id, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      "title" => Keyword.get(opts, :title, "Test Window"),
      "organization_id" => org_id,
      "start_time" => DateTime.add(now, 3600, :second),
      "end_time" => DateTime.add(now, 7200, :second)
    }

    {:ok, window} = Maintenance.create_maintenance_window(attrs)
    window
  end

  describe "GET /api/maintenance-windows" do
    test "lists windows for the current organization", %{conn: conn, org: org} do
      window = create_window(org.id)

      conn = get(conn, ~p"/api/maintenance-windows")

      response = json_response(conn, 200)
      assert [data] = response["data"]
      assert data["id"] == window.id
      assert data["title"] == "Test Window"
    end

    test "does not return windows from other organizations", %{conn: conn} do
      other_org = organization_fixture()
      create_window(other_org.id)

      conn = get(conn, ~p"/api/maintenance-windows")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "filters by status", %{conn: conn, org: org} do
      create_window(org.id)

      conn = get(conn, ~p"/api/maintenance-windows", %{"status" => "active"})

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "filters by monitor_id", %{conn: conn, org: org, monitor: monitor} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Maintenance.create_maintenance_window(%{
          "title" => "Monitor-specific",
          "organization_id" => org.id,
          "monitor_id" => monitor.id,
          "start_time" => DateTime.add(now, 3600, :second),
          "end_time" => DateTime.add(now, 7200, :second)
        })

      create_window(org.id)

      conn = get(conn, ~p"/api/maintenance-windows", %{"monitor_id" => monitor.id})

      response = json_response(conn, 200)
      assert length(response["data"]) == 1
      assert hd(response["data"])["monitor_id"] == monitor.id
    end
  end

  describe "POST /api/maintenance-windows" do
    test "creates a maintenance window", %{conn: conn} do
      conn = post(conn, ~p"/api/maintenance-windows", future_window_params())

      response = json_response(conn, 201)
      assert response["data"]["title"] == "Scheduled Maintenance"
      assert response["data"]["status"] == "scheduled"
      assert response["data"]["recurrence"] == "none"
    end

    test "creates a window for a specific monitor", %{conn: conn, monitor: monitor} do
      conn =
        post(conn, ~p"/api/maintenance-windows", future_window_params(monitor_id: monitor.id))

      response = json_response(conn, 201)
      assert response["data"]["monitor_id"] == monitor.id
    end

    test "returns error without required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/maintenance-windows", %{})

      assert json_response(conn, 422)
    end

    test "returns error when end_time before start_time", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      conn =
        post(conn, ~p"/api/maintenance-windows", %{
          "title" => "Bad",
          "start_time" => DateTime.to_iso8601(DateTime.add(now, 7200, :second)),
          "end_time" => DateTime.to_iso8601(DateTime.add(now, 3600, :second))
        })

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/maintenance-windows/:id" do
    test "returns a specific window", %{conn: conn, org: org} do
      window = create_window(org.id, title: "Specific")

      conn = get(conn, ~p"/api/maintenance-windows/#{window.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == window.id
      assert response["data"]["title"] == "Specific"
    end

    test "returns 404 for window in different org", %{conn: conn} do
      other_org = organization_fixture()
      window = create_window(other_org.id)

      conn = get(conn, ~p"/api/maintenance-windows/#{window.id}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/maintenance-windows/:id" do
    test "updates the window", %{conn: conn, org: org} do
      window = create_window(org.id)

      conn =
        patch(conn, ~p"/api/maintenance-windows/#{window.id}", %{"title" => "Updated Title"})

      response = json_response(conn, 200)
      assert response["data"]["title"] == "Updated Title"
    end

    test "returns 404 when updating window from different org", %{conn: conn} do
      other_org = organization_fixture()
      window = create_window(other_org.id)

      conn =
        patch(conn, ~p"/api/maintenance-windows/#{window.id}", %{"title" => "Hacked"})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/maintenance-windows/:id" do
    test "deletes the window", %{conn: conn, org: org} do
      window = create_window(org.id)

      conn = delete(conn, ~p"/api/maintenance-windows/#{window.id}")

      assert conn.status == 204
    end

    test "returns 404 when deleting window from different org", %{conn: conn} do
      other_org = organization_fixture()
      window = create_window(other_org.id)

      conn = delete(conn, ~p"/api/maintenance-windows/#{window.id}")

      assert json_response(conn, 404)
    end
  end
end
