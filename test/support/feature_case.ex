defmodule Uptrack.FeatureCase do
  @moduledoc """
  This module defines the setup for feature tests using Wallaby.

  You may define functions here to be used as helpers in
  your feature tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature

      alias Uptrack.AppRepo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Uptrack.DataCase
      import Uptrack.FeatureCase
      import Wallaby.Query
    end
  end

  setup tags do
    Uptrack.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Helper to create a user for testing
  """
  def create_user(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test@example.com",
        name: "Test User",
        password: "secure_password_123",
        confirmed_at: DateTime.utc_now()
      })
      |> Uptrack.Accounts.create_user()

    user
  end

  @doc """
  Helper to create a user from OAuth data (simulates OAuth flow)
  """
  def create_oauth_user(provider \\ :github, attrs \\ %{}) do
    oauth_data = %{
      provider: to_string(provider),
      provider_id: "#{provider}_#{System.unique_integer()}",
      email: attrs[:email] || "oauth@example.com",
      name: attrs[:name] || "OAuth User"
    }

    {:ok, user} = Uptrack.Accounts.create_user_from_oauth(oauth_data)
    user
  end

  @doc """
  Mock OAuth provider response for testing
  """
  def mock_oauth_success(session, provider, user_data \\ %{}) do
    # This would be used with Bypass to mock OAuth provider responses
    default_data = %{
      provider: to_string(provider),
      provider_id: "#{provider}_test_id",
      email: "oauth@example.com",
      name: "OAuth Test User"
    }

    _user_data = Map.merge(default_data, user_data)

    # Return session for chaining - actual OAuth flow would be handled in integration tests
    session
  end
end