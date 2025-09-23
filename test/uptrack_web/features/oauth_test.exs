defmodule UptrackWeb.Features.OAuthTest do
  use Uptrack.FeatureCase, async: false

  import Wallaby.Query
  alias Uptrack.OAuthMock

  @moduletag :wallaby

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "GitHub OAuth integration" do
    test "successful GitHub OAuth flow creates user", %{session: session, bypass: bypass} do
      # Set up GitHub OAuth mock
      OAuthMock.setup_github_mock(bypass)

      # Configure test OAuth endpoints
      bypass_url = "http://localhost:#{bypass.port}"
      github_config = OAuthMock.oauth_config(:github, bypass_url)

      # Override GitHub OAuth configuration for this test
      Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, [
        client_id: github_config.client_id,
        client_secret: github_config.client_secret
      ])

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      # This would redirect to GitHub, then back to our callback
      |> OAuthMock.simulate_oauth_callback(:github)
      |> assert_has(css("h1", text: "Dashboard"))
      |> assert_has(css(".flash-success", text: "Successfully signed in with GitHub"))

      # Verify user was created in database
      user = Uptrack.Accounts.get_user_by_email("github@example.com")
      assert user
      assert user.provider == "github"
      assert user.name == "GitHub Test User"
    end

    test "GitHub OAuth error handling", %{session: session, bypass: bypass} do
      OAuthMock.setup_github_mock(bypass)

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_error(:github, "access_denied")
      |> assert_has(css("h1", text: "Sign up"))
      |> assert_has(css(".flash-error", text: "Authentication failed"))
    end

    test "existing GitHub user can sign in", %{session: session, bypass: bypass} do
      # Create existing OAuth user
      create_oauth_user(:github, %{
        email: "existing@example.com",
        name: "Existing User"
      })

      OAuthMock.setup_github_mock(bypass)

      session
      |> visit("/")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_callback(:github)
      |> assert_has(css("h1", text: "Dashboard"))
      |> assert_has(css(".flash-success", text: "Welcome back!"))
    end
  end

  describe "Google OAuth integration" do
    test "successful Google OAuth flow creates user", %{session: session, bypass: bypass} do
      OAuthMock.setup_google_mock(bypass)

      bypass_url = "http://localhost:#{bypass.port}"
      google_config = OAuthMock.oauth_config(:google, bypass_url)

      Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth2, [
        client_id: google_config.client_id,
        client_secret: google_config.client_secret
      ])

      session
      |> visit("/signup")
      |> click(link("Sign in with Google"))
      |> OAuthMock.simulate_oauth_callback(:google)
      |> assert_has(css("h1", text: "Dashboard"))
      |> assert_has(css(".flash-success", text: "Successfully signed in with Google"))

      # Verify user was created
      user = Uptrack.Accounts.get_user_by_email("google@example.com")
      assert user
      assert user.provider == "google"
      assert user.name == "Google Test User"
    end

    test "Google OAuth with existing email links accounts", %{session: session, bypass: bypass} do
      # Create user with email/password first
      create_user(%{email: "google@example.com", name: "Email User"})

      OAuthMock.setup_google_mock(bypass)

      session
      |> visit("/")
      |> click(link("Sign in with Google"))
      |> OAuthMock.simulate_oauth_callback(:google)
      |> assert_has(css("h1", text: "Dashboard"))
      |> assert_has(css(".flash-info", text: "Account linked with Google"))

      # Verify account was updated, not duplicated
      users = Uptrack.AppRepo.all(Uptrack.Accounts.User)
      assert length(users) == 1

      user = List.first(users)
      assert user.provider == "google"
      assert user.provider_id
    end
  end

  describe "OAuth error scenarios" do
    test "handles network timeout gracefully", %{session: session} do
      # Don't set up bypass, causing connection to fail
      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      # This should timeout and show error
      |> assert_has(css(".flash-error", text: "Authentication service unavailable"))
    end

    test "handles invalid OAuth state parameter", %{session: session, bypass: bypass} do
      OAuthMock.setup_github_mock(bypass)

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_callback(:github, state: "invalid_state")
      |> assert_has(css(".flash-error", text: "Invalid authentication state"))
    end

    test "handles OAuth provider returning invalid user data", %{session: session, bypass: bypass} do
      # Set up mock that returns invalid/incomplete user data
      Bypass.expect_once(bypass, "POST", "/login/oauth/access_token", fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"access_token" => "test_token"}))
      end)

      Bypass.expect_once(bypass, "GET", "/user", fn conn ->
        # Return incomplete user data (missing required fields)
        Plug.Conn.resp(conn, 200, Jason.encode!(%{"id" => 123}))
      end)

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_callback(:github)
      |> assert_has(css(".flash-error", text: "Unable to retrieve user information"))
    end
  end

  describe "session management with OAuth" do
    test "OAuth user session persists across page navigation", %{session: session, bypass: bypass} do
      OAuthMock.setup_github_mock(bypass)

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_callback(:github)
      |> assert_has(css("h1", text: "Dashboard"))
      |> visit("/monitors")
      |> assert_has(css("h1", text: "Monitors"))
      |> visit("/profile")
      |> assert_has(css("input[value='GitHub Test User']"))
    end

    test "OAuth user can log out", %{session: session, bypass: bypass} do
      OAuthMock.setup_github_mock(bypass)

      session
      |> visit("/signup")
      |> click(link("Sign in with GitHub"))
      |> OAuthMock.simulate_oauth_callback(:github)
      |> click(link("Logout"))
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> visit("/dashboard")
      |> assert_has(text("Please sign in to access"))
    end
  end
end