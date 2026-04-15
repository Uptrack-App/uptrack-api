defmodule UptrackWeb.UserAuth do
  @moduledoc """
  Authentication helpers for LiveViews.

  Provides on_mount hooks to require authenticated users and
  load organization context for protected routes.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Uptrack.{Accounts, Organizations}

  @doc """
  LiveView on_mount hook to require an authenticated user.

  Loads the current user and organization from the session and assigns them
  to the socket. Redirects to signup if not authenticated.

  ## Usage

      live_session :authenticated, on_mount: [{UptrackWeb.UserAuth, :require_authenticated_user}] do
        live "/dashboard", DashboardLive, :index
      end
  """
  def on_mount(:require_authenticated_user, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/auth/signup")}

      user_id ->
        user = Accounts.get_user!(user_id)
        organization = Organizations.get_organization!(user.organization_id)

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_organization, organization)}
    end
  end

  # LiveView on_mount hook for platform admin routes (staff only).
  def on_mount(:require_admin_user, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/auth/signup")}

      user_id ->
        user = Accounts.get_user!(user_id)

        if user.is_admin do
          {:cont, assign(socket, :current_user, user)}
        else
          {:halt, redirect(socket, to: "/dashboard")}
        end
    end
  end

  # LiveView on_mount hook for optionally authenticated routes.
  # Loads user and organization if authenticated, but doesn't redirect if not.
  # Useful for public pages that show additional info for logged-in users.
  def on_mount(:fetch_current_user, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:cont,
         socket
         |> assign(:current_user, nil)
         |> assign(:current_organization, nil)}

      user_id ->
        user = Accounts.get_user!(user_id)
        organization = Organizations.get_organization(user.organization_id)

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_organization, organization)}
    end
  end
end
