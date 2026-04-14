defmodule UptrackWeb.Plugs.SetLocaleTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias UptrackWeb.Plugs.SetLocale

  defp call(conn), do: SetLocale.call(conn, SetLocale.init([]))

  describe "priority 1: authenticated user preferred_locale" do
    test "uses user's preferred_locale when present and supported" do
      user = %{preferred_locale: "ja"}
      conn = conn(:get, "/") |> assign(:current_user, user) |> call()

      assert conn.assigns.locale == "ja"
      assert Gettext.get_locale(UptrackWeb.Gettext) == "ja"
    end

    test "falls through when user has unsupported locale" do
      user = %{preferred_locale: "xx"}

      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "de")
        |> assign(:current_user, user)
        |> call()

      assert conn.assigns.locale == "de"
    end
  end

  describe "priority 2: LOCALE cookie" do
    test "uses LOCALE cookie for unauthenticated requests" do
      conn =
        conn(:get, "/")
        |> put_req_cookie("LOCALE", "de")
        |> fetch_cookies()
        |> call()

      assert conn.assigns.locale == "de"
    end

    test "ignores unsupported locale in cookie" do
      conn =
        conn(:get, "/")
        |> put_req_cookie("LOCALE", "xx")
        |> fetch_cookies()
        |> put_req_header("accept-language", "es")
        |> call()

      assert conn.assigns.locale == "es"
    end
  end

  describe "priority 3: Accept-Language header" do
    test "uses first supported locale from Accept-Language" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "ja,en-US;q=0.9,en;q=0.8")
        |> call()

      assert conn.assigns.locale == "ja"
    end

    test "falls through unsupported locales to find first supported" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "zh-TW,zh;q=0.9,de;q=0.8")
        |> call()

      assert conn.assigns.locale == "de"
    end

    test "handles short language codes like 'en-US' matching 'en'" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "en-US")
        |> call()

      assert conn.assigns.locale == "en"
    end
  end

  describe "priority 4: default fallback" do
    test "defaults to 'en' when no locale signals present" do
      conn = conn(:get, "/") |> call()

      assert conn.assigns.locale == "en"
    end

    test "defaults to 'en' when Accept-Language contains only unsupported locales" do
      conn =
        conn(:get, "/")
        |> put_req_header("accept-language", "zh-TW,ar")
        |> call()

      assert conn.assigns.locale == "en"
    end
  end
end
