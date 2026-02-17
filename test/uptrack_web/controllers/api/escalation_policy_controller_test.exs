defmodule UptrackWeb.Api.EscalationPolicyControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Escalation

  @moduletag :capture_log

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    channel = alert_channel_fixture(organization_id: org.id, user_id: user.id)
    {:ok, conn: conn, user: user, org: org, channel: channel}
  end

  defp create_policy(org_id, name \\ "Test Policy") do
    {:ok, policy} =
      Escalation.create_policy(%{
        "name" => name,
        "organization_id" => org_id
      })

    policy
  end

  describe "GET /api/escalation-policies" do
    test "lists policies for the current organization", %{conn: conn, org: org} do
      policy = create_policy(org.id)

      conn = get(conn, ~p"/api/escalation-policies")

      response = json_response(conn, 200)
      assert [data] = response["data"]
      assert data["id"] == policy.id
      assert data["name"] == "Test Policy"
    end

    test "does not return policies from other organizations", %{conn: conn} do
      other_org = organization_fixture()
      create_policy(other_org.id)

      conn = get(conn, ~p"/api/escalation-policies")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "returns 401 without authentication" do
      conn =
        build_conn()
        |> get(~p"/api/escalation-policies")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/escalation-policies" do
    test "creates a policy", %{conn: conn} do
      conn =
        post(conn, ~p"/api/escalation-policies", %{
          "name" => "Critical Alert",
          "description" => "For critical issues"
        })

      response = json_response(conn, 201)
      assert response["data"]["name"] == "Critical Alert"
      assert response["data"]["description"] == "For critical issues"
      assert is_list(response["data"]["steps"])
    end

    test "creates a policy with steps", %{conn: conn, channel: channel} do
      conn =
        post(conn, ~p"/api/escalation-policies", %{
          "name" => "Multi-step",
          "steps" => [
            %{"alert_channel_id" => channel.id, "step_order" => 1, "delay_minutes" => 0},
            %{"alert_channel_id" => channel.id, "step_order" => 2, "delay_minutes" => 10}
          ]
        })

      response = json_response(conn, 201)
      assert length(response["data"]["steps"]) == 2
    end

    test "returns error without name", %{conn: conn} do
      conn = post(conn, ~p"/api/escalation-policies", %{})

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/escalation-policies/:id" do
    test "returns a specific policy", %{conn: conn, org: org} do
      policy = create_policy(org.id, "My Policy")

      conn = get(conn, ~p"/api/escalation-policies/#{policy.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == policy.id
      assert response["data"]["name"] == "My Policy"
    end

    test "returns 404 for policy in different org", %{conn: conn} do
      other_org = organization_fixture()
      policy = create_policy(other_org.id)

      conn = get(conn, ~p"/api/escalation-policies/#{policy.id}")

      assert json_response(conn, 404)
    end

    test "returns 404 for nonexistent policy", %{conn: conn} do
      conn = get(conn, ~p"/api/escalation-policies/#{Uniq.UUID.uuid7()}")

      assert json_response(conn, 404)
    end
  end

  describe "PATCH /api/escalation-policies/:id" do
    test "updates the policy", %{conn: conn, org: org} do
      policy = create_policy(org.id)

      conn = patch(conn, ~p"/api/escalation-policies/#{policy.id}", %{"name" => "Updated"})

      response = json_response(conn, 200)
      assert response["data"]["name"] == "Updated"
    end

    test "replaces steps on update", %{conn: conn, org: org, channel: channel} do
      policy = create_policy(org.id)

      conn =
        patch(conn, ~p"/api/escalation-policies/#{policy.id}", %{
          "steps" => [
            %{"alert_channel_id" => channel.id, "step_order" => 1, "delay_minutes" => 5}
          ]
        })

      response = json_response(conn, 200)
      assert length(response["data"]["steps"]) == 1
      assert hd(response["data"]["steps"])["delay_minutes"] == 5
    end

    test "returns 404 when updating policy from different org", %{conn: conn} do
      other_org = organization_fixture()
      policy = create_policy(other_org.id)

      conn = patch(conn, ~p"/api/escalation-policies/#{policy.id}", %{"name" => "Hacked"})

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/escalation-policies/:id" do
    test "deletes the policy", %{conn: conn, org: org} do
      policy = create_policy(org.id)

      conn = delete(conn, ~p"/api/escalation-policies/#{policy.id}")

      assert conn.status == 204
    end

    test "returns 404 when deleting policy from different org", %{conn: conn} do
      other_org = organization_fixture()
      policy = create_policy(other_org.id)

      conn = delete(conn, ~p"/api/escalation-policies/#{policy.id}")

      assert json_response(conn, 404)
    end
  end
end
