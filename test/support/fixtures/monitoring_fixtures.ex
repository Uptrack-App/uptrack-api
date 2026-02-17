defmodule Uptrack.MonitoringFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Uptrack.Monitoring` context.
  """

  alias Uptrack.Organizations

  @doc """
  Generate an organization for testing.
  """
  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      attrs
      |> Enum.into(%{
        name: "Test Organization #{System.unique_integer([:positive])}",
        slug: "test-org-#{System.unique_integer([:positive])}"
      })
      |> Organizations.create_organization()

    organization
  end

  @doc """
  Generate a user with organization for testing.
  """
  def user_with_org_fixture(attrs \\ %{}) do
    org = organization_fixture()

    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "user#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        password: "test_password_123",
        organization_id: org.id
      })
      |> Uptrack.Accounts.create_user()

    {user, org}
  end

  @doc """
  Generate a monitor.
  """
  def monitor_fixture(attrs \\ %{}) do
    # Create org and user if not provided
    {user_id, org_id} =
      case {attrs[:user_id], attrs[:organization_id]} do
        {nil, nil} ->
          {user, org} = user_with_org_fixture()
          {user.id, org.id}

        {user_id, org_id} ->
          {user_id, org_id}
      end

    desired_status = attrs[:status] || "active"

    {:ok, monitor} =
      attrs
      |> Enum.into(%{
        name: "Test Monitor #{System.unique_integer([:positive])}",
        url: "https://example.com",
        monitor_type: "http",
        interval: 300,
        timeout: 30,
        status: "active",
        description: "Test monitor description",
        settings: %{},
        alert_contacts: [],
        organization_id: org_id,
        user_id: user_id
      })
      |> Uptrack.Monitoring.create_monitor()

    # create_changeset forces status to "active", so update if a different status was requested
    if desired_status != "active" do
      {:ok, monitor} = Uptrack.Monitoring.update_monitor(monitor, %{status: desired_status})
      monitor
    else
      monitor
    end
  end

  @doc """
  Generate a status page.
  """
  def status_page_fixture(attrs \\ %{}) do
    {user_id, org_id} =
      case {attrs[:user_id], attrs[:organization_id]} do
        {nil, nil} ->
          {user, org} = user_with_org_fixture()
          {user.id, org.id}

        {user_id, org_id} ->
          {user_id, org_id}
      end

    {:ok, status_page} =
      attrs
      |> Enum.into(%{
        name: "Test Status Page",
        slug: "test-status-#{System.unique_integer([:positive])}",
        description: "Test status page",
        is_public: true,
        allow_subscriptions: true,
        default_language: "en",
        organization_id: org_id,
        user_id: user_id
      })
      |> Uptrack.Monitoring.create_status_page()

    status_page
  end

  @doc """
  Generate an escalation policy with 2 steps.
  """
  def escalation_policy_fixture(attrs \\ %{}) do
    {user_id, org_id} =
      case {attrs[:user_id], attrs[:organization_id]} do
        {nil, nil} ->
          {user, org} = user_with_org_fixture()
          {user.id, org.id}

        {user_id, org_id} ->
          {user_id, org_id}
      end

    # Create two alert channels for the steps
    ch1 = alert_channel_fixture(user_id: user_id, organization_id: org_id, name: "Escalation Email 1")
    ch2 = alert_channel_fixture(user_id: user_id, organization_id: org_id, name: "Escalation Email 2")

    {:ok, policy} =
      attrs
      |> Enum.into(%{
        name: "Test Policy #{System.unique_integer([:positive])}",
        organization_id: org_id
      })
      |> Uptrack.Escalation.create_policy()

    {:ok, _step1} =
      Uptrack.Escalation.add_step(%{
        escalation_policy_id: policy.id,
        alert_channel_id: ch1.id,
        step_order: 1,
        delay_minutes: 0
      })

    {:ok, _step2} =
      Uptrack.Escalation.add_step(%{
        escalation_policy_id: policy.id,
        alert_channel_id: ch2.id,
        step_order: 2,
        delay_minutes: 5
      })

    Uptrack.Escalation.get_policy(policy.id)
  end

  @doc """
  Generate a scheduled maintenance window.
  """
  def maintenance_window_fixture(attrs \\ %{}) do
    org_id =
      case attrs[:organization_id] do
        nil ->
          {_user, org} = user_with_org_fixture()
          org.id

        org_id ->
          org_id
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, window} =
      attrs
      |> Enum.into(%{
        title: "Test Maintenance #{System.unique_integer([:positive])}",
        start_time: DateTime.add(now, 3600, :second),
        end_time: DateTime.add(now, 7200, :second),
        recurrence: "none",
        organization_id: org_id
      })
      |> Uptrack.Maintenance.create_maintenance_window()

    window
  end

  @doc """
  Generate an alert channel.
  """
  def alert_channel_fixture(attrs \\ %{}) do
    {user_id, org_id} =
      case {attrs[:user_id], attrs[:organization_id]} do
        {nil, nil} ->
          {user, org} = user_with_org_fixture()
          {user.id, org.id}

        {user_id, org_id} ->
          {user_id, org_id}
      end

    {:ok, alert_channel} =
      attrs
      |> Enum.into(%{
        name: "Test Alert Channel",
        type: "email",
        config: %{"email" => "test@example.com"},
        is_active: true,
        organization_id: org_id,
        user_id: user_id
      })
      |> Uptrack.Monitoring.create_alert_channel()

    alert_channel
  end
end
