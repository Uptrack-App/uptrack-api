defmodule UptrackWeb.Plugs.SetLocale do
  @moduledoc """
  Resolves the active locale per request and applies it to Gettext.

  Priority chain:
  1. Authenticated user's `preferred_locale` from DB
  2. `LOCALE` cookie
  3. `Accept-Language` request header (first supported locale)
  4. `"en"` default
  """

  import Plug.Conn

  @supported_locales Uptrack.Accounts.User.supported_locales()
  @default_locale "en"

  def init(_opts), do: nil

  def call(conn, _opts) do
    locale = resolve_locale(conn)
    Gettext.put_locale(UptrackWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  defp resolve_locale(conn) do
    user_locale(conn) ||
      cookie_locale(conn) ||
      header_locale(conn) ||
      @default_locale
  end

  defp user_locale(%{assigns: %{current_user: %{preferred_locale: locale}}})
       when locale in @supported_locales,
       do: locale

  defp user_locale(_conn), do: nil

  defp cookie_locale(conn) do
    conn = fetch_cookies(conn)
    locale = conn.cookies["LOCALE"]
    if locale in @supported_locales, do: locale
  end

  defp header_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first("")
    |> parse_accept_language()
    |> Enum.find(&(&1 in @supported_locales))
  end

  # Parses "ja,en-US;q=0.9,en;q=0.8" → ["ja", "en-US", "en"]
  # Also tries short codes: "en-US" → also tries "en"
  defp parse_accept_language(""), do: []

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.flat_map(fn entry ->
      tag =
        entry
        |> String.split(";")
        |> List.first()
        |> String.trim()

      short = tag |> String.split("-") |> List.first()
      Enum.uniq([tag, short])
    end)
  end
end
