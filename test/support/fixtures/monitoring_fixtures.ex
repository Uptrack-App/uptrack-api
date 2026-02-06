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

    monitor
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
        channel_type: "email",
        config: %{"email" => "test@example.com"},
        enabled: true,
        organization_id: org_id,
        user_id: user_id
      })
      |> Uptrack.Monitoring.create_alert_channel()

    alert_channel
  end
end
