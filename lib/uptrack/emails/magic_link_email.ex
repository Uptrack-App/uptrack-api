defmodule Uptrack.Emails.MagicLinkEmail do
  @moduledoc "Email template for magic link authentication."

  import Swoosh.Email
  use Gettext, backend: UptrackWeb.Gettext

  @from_email {"Uptrack", "alerts@uptrack.app"}

  defp api_url do
    host = Application.get_env(:uptrack, UptrackWeb.Endpoint)[:url][:host] || "localhost"
    if host == "localhost", do: "http://localhost:4000", else: "https://#{host}"
  end

  def magic_link_email(email, raw_token, locale \\ "en") do
    Gettext.put_locale(UptrackWeb.Gettext, locale)
    # Link directly to API callback (same-origin cookie, SameSite=Lax safe)
    verify_url = "#{api_url()}/api/auth/magic-link/callback?token=#{raw_token}&email=#{URI.encode_www_form(email)}"

    new()
    |> to(email)
    |> from(@from_email)
    |> subject(gettext("Sign in to Uptrack"))
    |> html_body(html(verify_url))
    |> text_body(text(verify_url))
  end

  defp html(verify_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #13111c; color: #e5e5e5; padding: 40px 20px;">
      <div style="max-width: 480px; margin: 0 auto;">
        <h1 style="font-size: 24px; font-weight: 600; margin-bottom: 16px; color: #ffffff;">Sign in to Uptrack</h1>
        <p style="font-size: 16px; line-height: 1.6; color: #a1a1aa; margin-bottom: 24px;">
          Click the button below to sign in. This link expires in 15 minutes and can only be used once.
        </p>
        <a href="#{verify_url}" style="display: inline-block; background-color: #7c3aed; color: #ffffff; text-decoration: none; padding: 12px 32px; border-radius: 8px; font-size: 16px; font-weight: 600;">
          Sign in to Uptrack &rarr;
        </a>
        <p style="font-size: 13px; color: #71717a; margin-top: 32px; line-height: 1.5;">
          If you didn't request this email, you can safely ignore it. No account will be created unless you click the link.
        </p>
        <hr style="border: none; border-top: 1px solid #27272a; margin: 32px 0;" />
        <p style="font-size: 12px; color: #52525b;">
          Uptrack &mdash; Uptime monitoring that doesn't cry wolf.
        </p>
      </div>
    </body>
    </html>
    """
  end

  defp text(verify_url) do
    """
    Sign in to Uptrack

    Click the link below to sign in:
    #{verify_url}

    This link expires in 15 minutes and can only be used once.

    If you didn't request this, ignore this email.

    — Uptrack
    """
  end
end
