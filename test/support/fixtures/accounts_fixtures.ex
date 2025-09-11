defmodule Uptrack.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Uptrack.Accounts` context.
  """

  @doc """
  Generate a unique user email.
  """
  def unique_user_email, do: "some email#{System.unique_integer([:positive])}"

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        confirmed_at: ~N[2025-09-10 02:16:00],
        email: unique_user_email(),
        hashed_password: "some hashed_password",
        name: "some name",
        provider: "some provider",
        provider_id: "some provider_id"
      })
      |> Uptrack.Accounts.create_user()

    user
  end
end
