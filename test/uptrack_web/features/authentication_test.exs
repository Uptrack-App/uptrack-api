defmodule UptrackWeb.Features.AuthenticationTest do
  use Uptrack.FeatureCase, async: false

  import Wallaby.Query

  @moduletag :wallaby

  describe "user authentication flow" do
    test "user can visit signup page", %{session: session} do
      session
      |> visit("/signup")
      |> assert_has(css("h1", text: "Sign up"))
      |> assert_has(css("form"))
      |> assert_has(link("Sign in with GitHub"))
      |> assert_has(link("Sign in with Google"))
    end

    test "user can register with email and password", %{session: session} do
      session
      |> visit("/signup")
      |> fill_in(css("input[name='user[email]']"), with: "newuser@example.com")
      |> fill_in(css("input[name='user[name]']"), with: "New User")
      |> fill_in(css("input[name='user[password]']"), with: "secure_password_123")
      |> click(css("button[type='submit']"))
      |> assert_has(css(".flash-success", text: "User created successfully"))
    end

    test "user registration validates password length", %{session: session} do
      session
      |> visit("/signup")
      |> fill_in(css("input[name='user[email]']"), with: "test@example.com")
      |> fill_in(css("input[name='user[name]']"), with: "Test User")
      |> fill_in(css("input[name='user[password]']"), with: "short")
      |> click(css("button[type='submit']"))
      |> assert_has(css(".error", text: "should be at least 12 character(s)"))
    end

    test "user registration validates email format", %{session: session} do
      session
      |> visit("/signup")
      |> fill_in(css("input[name='user[email]']"), with: "invalid-email")
      |> fill_in(css("input[name='user[name]']"), with: "Test User")
      |> fill_in(css("input[name='user[password]']"), with: "secure_password_123")
      |> click(css("button[type='submit']"))
      |> assert_has(css(".error", text: "must have the @ sign and no spaces"))
    end

    test "prevents duplicate email registration", %{session: session} do
      # Create a user first
      create_user(%{email: "existing@example.com"})

      session
      |> visit("/signup")
      |> fill_in(css("input[name='user[email]']"), with: "existing@example.com")
      |> fill_in(css("input[name='user[name]']"), with: "Another User")
      |> fill_in(css("input[name='user[password]']"), with: "secure_password_123")
      |> click(css("button[type='submit']"))
      |> assert_has(css(".error", text: "has already been taken"))
    end
  end

  describe "OAuth authentication" do
    test "displays OAuth login options", %{session: session} do
      session
      |> visit("/")
      |> assert_has(link("Sign in with GitHub"))
      |> assert_has(link("Sign in with Google"))
    end

    test "GitHub OAuth link has correct URL", %{session: session} do
      session
      |> visit("/")
      |> find(link("Sign in with GitHub"))
      |> assert_has(css("a[href='/auth/github']"))
    end

    test "Google OAuth link has correct URL", %{session: session} do
      session
      |> visit("/")
      |> find(link("Sign in with Google"))
      |> assert_has(css("a[href='/auth/google']"))
    end
  end

  describe "session management" do
    test "user can log out", %{session: session} do
      user = create_user()

      session
      |> visit("/")
      |> click(link("Dashboard"))
      |> assert_has(css("h1", text: "Dashboard"))
      |> click(link("Logout"))
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
    end

    test "protected routes redirect to login", %{session: session} do
      session
      |> visit("/dashboard")
      |> assert_has(css("h1", text: "Welcome to Uptrack"))
      |> assert_has(text("Please sign in to access your dashboard"))
    end
  end

  describe "user profile management" do
    test "user can view profile after authentication", %{session: session} do
      user = create_user(%{name: "Profile User", email: "profile@example.com"})

      # Simulate logged in user (you'll need to implement session creation)
      session
      |> authenticate_user(user)
      |> visit("/profile")
      |> assert_has(css("input[value='Profile User']"))
      |> assert_has(css("input[value='profile@example.com']"))
    end

    test "user can update notification preferences", %{session: session} do
      user = create_user()

      session
      |> authenticate_user(user)
      |> visit("/profile")
      |> check(css("input[name='notification_preferences[email_alerts]']"))
      |> click(css("button", text: "Update Profile"))
      |> assert_has(css(".flash-success", text: "Profile updated successfully"))
    end
  end

  # Helper function to simulate user authentication in tests
  defp authenticate_user(session, user) do
    # This would typically involve setting up the session
    # For now, we'll simulate it by visiting a login endpoint
    session
    |> visit("/test/login/#{user.id}")
  end
end