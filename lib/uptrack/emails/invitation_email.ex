defmodule Uptrack.Emails.InvitationEmail do
  @moduledoc """
  Email template for team member invitations.
  """

  import Swoosh.Email
  use Gettext, backend: UptrackWeb.Gettext
  alias Uptrack.Teams.TeamInvitation

  @from_email {"Uptrack", "team@uptrack.app"}

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")

  def invitation_email(%TeamInvitation{} = invitation, organization_name, inviter_name, locale \\ "en") do
    Gettext.put_locale(UptrackWeb.Gettext, locale)
    accept_url = "#{app_url()}/invitations/#{invitation.token}"

    new()
    |> to(invitation.email)
    |> from(@from_email)
    |> subject(gettext("You've been invited to %{org} on Uptrack", org: organization_name))
    |> html_body(invitation_html(invitation, organization_name, inviter_name, accept_url))
    |> text_body(invitation_text(invitation, organization_name, inviter_name, accept_url))
  end

  defp invitation_html(invitation, org_name, inviter_name, accept_url) do
    role_label = invitation.role |> to_string() |> String.replace("_", " ") |> String.capitalize()

    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Team Invitation</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
            .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
            .header { background: #3b82f6; color: white; padding: 24px; text-align: center; }
            .header h1 { margin: 0; font-size: 24px; }
            .content { padding: 24px; }
            .invite-box { background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 16px; margin: 16px 0; }
            .info-table { width: 100%; border-collapse: collapse; margin: 16px 0; }
            .info-table td { padding: 8px 0; border-bottom: 1px solid #e5e5e5; }
            .info-table td:first-child { font-weight: 600; width: 120px; color: #666; }
            .btn { display: inline-block; background: #3b82f6; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; margin: 16px 0; font-weight: 600; }
            .footer { background: #f9f9f9; padding: 16px 24px; font-size: 12px; color: #666; text-align: center; }
            .link-fallback { color: #666; font-size: 14px; word-break: break-all; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>Team Invitation</h1>
            </div>
            <div class="content">
                <div class="invite-box">
                    <h2 style="margin-top: 0; color: #1d4ed8;">You're invited to #{org_name}</h2>
                    <p><strong>#{inviter_name}</strong> has invited you to join <strong>#{org_name}</strong> on Uptrack.</p>
                </div>

                <table class="info-table">
                    <tr>
                        <td>Organization:</td>
                        <td>#{org_name}</td>
                    </tr>
                    <tr>
                        <td>Role:</td>
                        <td>#{role_label}</td>
                    </tr>
                    <tr>
                        <td>Expires:</td>
                        <td>#{Calendar.strftime(invitation.expires_at, "%B %d, %Y")}</td>
                    </tr>
                </table>

                <div style="text-align: center;">
                    <a href="#{accept_url}" class="btn" style="display: inline-block; background: #3b82f6; color: #ffffff; padding: 14px 28px; text-decoration: none; border-radius: 6px; margin: 16px 0; font-weight: 600;">Accept Invitation</a>
                </div>

                <p class="link-fallback">Or copy and paste this link into your browser:<br>#{accept_url}</p>

                <p style="color: #666; margin-top: 24px;">
                    If you don't recognize this invitation, you can safely ignore this email.
                </p>
            </div>
            <div class="footer">
                <p>Powered by <a href="https://uptrack.app">Uptrack</a></p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp invitation_text(invitation, org_name, inviter_name, accept_url) do
    role_label = invitation.role |> to_string() |> String.replace("_", " ") |> String.capitalize()

    """
    You're invited to #{org_name} on Uptrack

    #{inviter_name} has invited you to join #{org_name}.

    Organization: #{org_name}
    Role: #{role_label}
    Expires: #{Calendar.strftime(invitation.expires_at, "%B %d, %Y")}

    Accept your invitation: #{accept_url}

    If you don't recognize this invitation, you can safely ignore this email.

    ---
    Powered by Uptrack
    """
  end
end
