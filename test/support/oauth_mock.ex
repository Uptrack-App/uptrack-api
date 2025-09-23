defmodule Uptrack.OAuthMock do
  @moduledoc """
  Mock OAuth providers for testing authentication flows.

  This module provides helpers to mock GitHub and Google OAuth responses
  using Bypass for integration testing.
  """

  @doc """
  Sets up a mock GitHub OAuth server
  """
  def setup_github_mock(bypass) do
    # Mock GitHub OAuth token endpoint
    Bypass.expect_once(bypass, "POST", "/login/oauth/access_token", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "access_token" => "github_test_token",
        "token_type" => "bearer",
        "scope" => "user:email"
      }))
    end)

    # Mock GitHub API user endpoint
    Bypass.expect_once(bypass, "GET", "/user", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "id" => 12345,
        "login" => "testuser",
        "email" => "github@example.com",
        "name" => "GitHub Test User",
        "avatar_url" => "https://avatars.githubusercontent.com/u/12345"
      }))
    end)

    # Mock GitHub API emails endpoint
    Bypass.expect_once(bypass, "GET", "/user/emails", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!([
        %{
          "email" => "github@example.com",
          "verified" => true,
          "primary" => true,
          "visibility" => "public"
        }
      ]))
    end)
  end

  @doc """
  Sets up a mock Google OAuth server
  """
  def setup_google_mock(bypass) do
    # Mock Google OAuth token endpoint
    Bypass.expect_once(bypass, "POST", "/token", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "access_token" => "google_test_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "id_token" => "test_id_token"
      }))
    end)

    # Mock Google API userinfo endpoint
    Bypass.expect_once(bypass, "GET", "/oauth2/v2/userinfo", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "id" => "google_user_123",
        "email" => "google@example.com",
        "verified_email" => true,
        "name" => "Google Test User",
        "picture" => "https://lh3.googleusercontent.com/test"
      }))
    end)
  end

  @doc """
  Creates test OAuth configuration for a specific provider
  """
  def oauth_config(provider, bypass_url) do
    case provider do
      :github ->
        %{
          client_id: "test_github_client_id",
          client_secret: "test_github_client_secret",
          authorize_url: "#{bypass_url}/login/oauth/authorize",
          access_token_url: "#{bypass_url}/login/oauth/access_token",
          user_url: "#{bypass_url}/user"
        }

      :google ->
        %{
          client_id: "test_google_client_id",
          client_secret: "test_google_client_secret",
          authorize_url: "#{bypass_url}/oauth2/auth",
          token_url: "#{bypass_url}/token",
          userinfo_url: "#{bypass_url}/oauth2/v2/userinfo"
        }
    end
  end

  @doc """
  Simulates an OAuth callback with a successful authorization code
  """
  def simulate_oauth_callback(session, provider, opts \\ []) do
    code = Keyword.get(opts, :code, "test_authorization_code")
    state = Keyword.get(opts, :state, "test_state")

    session
    |> Wallaby.Browser.visit("/auth/#{provider}/callback?code=#{code}&state=#{state}")
  end

  @doc """
  Simulates an OAuth callback with an error
  """
  def simulate_oauth_error(session, provider, error \\ "access_denied") do
    session
    |> Wallaby.Browser.visit("/auth/#{provider}/callback?error=#{error}")
  end
end