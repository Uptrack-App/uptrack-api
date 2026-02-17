defmodule Uptrack.EscalationTest do
  use Uptrack.DataCase

  alias Uptrack.Escalation
  alias Uptrack.Escalation.{EscalationPolicy, EscalationStep}

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    channel = alert_channel_fixture(organization_id: org.id, user_id: user.id)
    {:ok, user: user, org: org, channel: channel}
  end

  describe "create_policy/1" do
    test "creates a policy with valid attrs", %{org: org} do
      assert {:ok, %EscalationPolicy{} = policy} =
               Escalation.create_policy(%{
                 "name" => "Critical",
                 "description" => "Critical escalation",
                 "organization_id" => org.id
               })

      assert policy.name == "Critical"
      assert policy.description == "Critical escalation"
      assert policy.organization_id == org.id
    end

    test "requires name and organization_id" do
      assert {:error, changeset} = Escalation.create_policy(%{})
      assert errors_on(changeset) |> Map.has_key?(:name)
      assert errors_on(changeset) |> Map.has_key?(:organization_id)
    end
  end

  describe "list_policies/1" do
    test "returns policies for the given org", %{org: org} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "P1", "organization_id" => org.id})

      assert policies = Escalation.list_policies(org.id)
      assert length(policies) == 1
      assert hd(policies).id == policy.id
    end

    test "does not return policies from other orgs", %{org: org} do
      other_org = organization_fixture()
      {:ok, _} = Escalation.create_policy(%{"name" => "Other", "organization_id" => other_org.id})

      assert Escalation.list_policies(org.id) == []
    end
  end

  describe "get_organization_policy/2" do
    test "returns policy belonging to org", %{org: org} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "P1", "organization_id" => org.id})

      assert found = Escalation.get_organization_policy(org.id, policy.id)
      assert found.id == policy.id
    end

    test "returns nil for policy in different org", %{org: org} do
      other_org = organization_fixture()
      {:ok, policy} = Escalation.create_policy(%{"name" => "Other", "organization_id" => other_org.id})

      assert Escalation.get_organization_policy(org.id, policy.id) == nil
    end
  end

  describe "update_policy/2" do
    test "updates policy name", %{org: org} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "Old", "organization_id" => org.id})

      assert {:ok, updated} = Escalation.update_policy(policy, %{"name" => "New"})
      assert updated.name == "New"
    end
  end

  describe "delete_policy/1" do
    test "deletes the policy", %{org: org} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "ToDelete", "organization_id" => org.id})

      assert {:ok, _} = Escalation.delete_policy(policy)
      assert Escalation.get_policy(policy.id) == nil
    end
  end

  describe "add_step/1 and replace_steps/2" do
    test "adds a step to a policy", %{org: org, channel: channel} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "P1", "organization_id" => org.id})

      assert {:ok, %EscalationStep{} = step} =
               Escalation.add_step(%{
                 "escalation_policy_id" => policy.id,
                 "alert_channel_id" => channel.id,
                 "step_order" => 1,
                 "delay_minutes" => 5
               })

      assert step.step_order == 1
      assert step.delay_minutes == 5
    end

    test "replace_steps replaces all steps", %{org: org, channel: channel} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "P1", "organization_id" => org.id})

      # Add initial step
      Escalation.add_step(%{
        "escalation_policy_id" => policy.id,
        "alert_channel_id" => channel.id,
        "step_order" => 1,
        "delay_minutes" => 0
      })

      # Replace with two new steps
      {user2, _} = user_with_org_fixture()
      channel2 = alert_channel_fixture(organization_id: org.id, user_id: user2.id)

      {:ok, new_steps} =
        Escalation.replace_steps(policy.id, [
          %{"alert_channel_id" => channel.id, "step_order" => 1, "delay_minutes" => 0},
          %{"alert_channel_id" => channel2.id, "step_order" => 2, "delay_minutes" => 10}
        ])

      assert length(new_steps) == 2
    end
  end

  describe "max_step_order/1" do
    test "returns 0 for policy with no steps", %{org: org} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "Empty", "organization_id" => org.id})

      assert Escalation.max_step_order(policy.id) == 0
    end

    test "returns max step order", %{org: org, channel: channel} do
      {:ok, policy} =
        Escalation.create_policy(%{"name" => "P1", "organization_id" => org.id})

      Escalation.add_step(%{
        "escalation_policy_id" => policy.id,
        "alert_channel_id" => channel.id,
        "step_order" => 3,
        "delay_minutes" => 0
      })

      assert Escalation.max_step_order(policy.id) == 3
    end
  end
end
