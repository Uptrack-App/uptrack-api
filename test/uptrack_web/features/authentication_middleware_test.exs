defmodule UptrackWeb.Features.AuthenticationMiddlewareTest do
  use Uptrack.FeatureCase, async: false

  import Wallaby.Query

  @moduletag :wallaby

  describe "protected routes" do
    test "dashboard requires authentication", %{session: session} do
      session
      |> visit("/dashboard")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Please sign in to access your dashboard"))
    end

    test "monitors page requires authentication", %{session: session} do
      session
      |> visit("/monitors")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Please sign in to access"))
    end

    test "profile page requires authentication", %{session: session} do
      session
      |> visit("/profile")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Please sign in to access"))
    end

    test "incidents page requires authentication", %{session: session} do
      session
      |> visit("/incidents")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Please sign in to access"))
    end

    test "alerts page requires authentication", %{session: session} do
      session
      |> visit("/alerts")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Please sign in to access"))
    end
  end

  describe "public routes" do
    test "home page is accessible without authentication", %{session: session} do
      session
      |> visit("/")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(link("Sign in with GitHub"))
      |> assert_has(link("Sign in with Google"))
    end

    test "signup page is accessible without authentication", %{session: session} do
      session
      |> visit("/signup")
      |> assert_has(css("h1", text: "Sign up"))
      |> assert_has(css("form"))
    end

    test "OAuth callback routes are accessible", %{session: session} do
      # These routes should be accessible for OAuth flow completion
      session
      |> visit("/auth/github/callback?error=access_denied")
      |> assert_has(css(".flash-error"))

      session
      |> visit("/auth/google/callback?error=access_denied")
      |> assert_has(css(".flash-error"))
    end
  end

  describe "authenticated user access" do
    test "authenticated user can access protected routes", %{session: session} do
      user = create_user()

      session
      |> authenticate_user(user)
      |> visit("/dashboard")
      |> assert_has(css("h1", text: "Dashboard"))
      |> visit("/monitors")
      |> assert_has(css("h1", text: "Monitors"))
      |> visit("/profile")
      |> assert_has(css("input[value='#{user.name}']"))
    end

    test "authenticated user sees logout option", %{session: session} do
      user = create_user()

      session
      |> authenticate_user(user)
      |> visit("/dashboard")
      |> assert_has(link("Logout"))
      |> assert_has(Wallaby.Query.text("Welcome, #{user.name}"))
    end
  end

  describe "session expiration" do
    test "expired session redirects to login", %{session: session} do
      user = create_user()

      # Simulate expired session by clearing it
      session
      |> authenticate_user(user)
      |> visit("/dashboard")
      |> assert_has(css("h1", text: "Dashboard"))
      |> expire_session()
      |> visit("/dashboard")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(Wallaby.Query.text("Your session has expired"))
    end
  end

  describe "unauthorized actions" do
    test "user cannot access other user's data", %{session: session} do
      user1 = create_user(%{email: "user1@example.com"})
      user2 = create_user(%{email: "user2@example.com"})

      # Create a monitor for user2
      {:ok, monitor} = Uptrack.Monitoring.create_monitor(user2, %{
        name: "User2's Monitor",
        url: "https://example.com",
        monitor_type: "http"
      })

      session
      |> authenticate_user(user1)
      |> visit("/monitors/#{monitor.id}")
      |> assert_has(css(".flash-error", text: "Access denied"))
      |> assert_has(css("h1", text: "Dashboard"))
    end

    test "user cannot edit other user's monitors", %{session: session} do
      user1 = create_user(%{email: "user1@example.com"})
      user2 = create_user(%{email: "user2@example.com"})

      {:ok, monitor} = Uptrack.Monitoring.create_monitor(user2, %{
        name: "User2's Monitor",
        url: "https://example.com",
        monitor_type: "http"
      })

      session
      |> authenticate_user(user1)
      |> visit("/monitors/#{monitor.id}/edit")
      |> assert_has(css(".flash-error", text: "Access denied"))
    end
  end

  # Helper functions
  defp authenticate_user(session, user) do
    # This would typically set the user_id in the session
    # For testing, we might create a test route that simulates login
    session
    |> visit("/test/auth/login/#{user.id}")
  end

  defp expire_session(session) do
    # Simulate session expiration by visiting a test route that clears session
    session
    |> visit("/test/auth/expire")
  end
end