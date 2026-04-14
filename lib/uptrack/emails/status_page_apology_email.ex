defmodule Uptrack.Emails.StatusPageApologyEmail do
  import Swoosh.Email

  @from_email {"Uptrack", "hello@uptrack.app"}

  def apology_email(to_email, to_name) do
    greeting = if to_name && to_name != "", do: "Hi #{String.split(to_name, " ") |> List.first()},", else: "Hi,"

    new()
    |> to({to_name || "", to_email})
    |> from(@from_email)
    |> subject("Service Notice: Status Page Display Issue (Now Resolved)")
    |> html_body(html(greeting))
    |> text_body(text(greeting))
  end

  defp html(greeting) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #13111c; color: #e5e5e5; padding: 40px 20px;">
      <div style="max-width: 520px; margin: 0 auto;">
        <h1 style="font-size: 22px; font-weight: 600; margin-bottom: 8px; color: #ffffff;">Service Notice</h1>
        <p style="font-size: 15px; line-height: 1.6; color: #a1a1aa; margin-bottom: 24px; margin-top: 0;">Status Page Display Issue &mdash; Now Resolved</p>

        <p style="font-size: 15px; line-height: 1.6; color: #e5e5e5; margin-bottom: 16px;">#{greeting}</p>

        <p style="font-size: 15px; line-height: 1.6; color: #e5e5e5; margin-bottom: 16px;">
          We're writing to let you know about a display issue that recently affected Uptrack status pages, including yours.
        </p>

        <h2 style="font-size: 16px; font-weight: 600; color: #ffffff; margin-bottom: 8px;">What happened</h2>
        <p style="font-size: 15px; line-height: 1.6; color: #a1a1aa; margin-bottom: 16px;">
          For a period of time, status pages were incorrectly showing all monitors as <strong style="color: #e5e5e5;">"Unknown"</strong> instead of their actual status. This was caused by a bug in how the public status page read monitor data — it was querying the wrong data source and returning empty results instead of live check data.
        </p>

        <h2 style="font-size: 16px; font-weight: 600; color: #ffffff; margin-bottom: 8px;">Your monitors were working fine</h2>
        <p style="font-size: 15px; line-height: 1.6; color: #a1a1aa; margin-bottom: 16px;">
          The monitoring itself was <strong style="color: #e5e5e5;">not affected</strong>. Your websites were being checked on schedule throughout this period, and alerts would have fired normally for any real downtime. Only the public status page display was incorrect.
        </p>

        <h2 style="font-size: 16px; font-weight: 600; color: #ffffff; margin-bottom: 8px;">What we did</h2>
        <p style="font-size: 15px; line-height: 1.6; color: #a1a1aa; margin-bottom: 24px;">
          We identified the root cause and deployed a fix. Your status page now correctly reflects the real-time status of all your monitors.
        </p>

        <p style="font-size: 15px; line-height: 1.6; color: #e5e5e5; margin-bottom: 24px;">
          We're sorry for any confusion this caused — especially if visitors to your status page were left uncertain about your services' availability. We take reliability seriously, and we'll be reviewing our monitoring pipeline to prevent similar issues.
        </p>

        <p style="font-size: 15px; line-height: 1.6; color: #e5e5e5; margin-bottom: 0;">
          If you have any questions, reply to this email and we'll get back to you.
        </p>

        <hr style="border: none; border-top: 1px solid #27272a; margin: 32px 0;" />
        <p style="font-size: 12px; color: #52525b; margin: 0;">
          Uptrack &mdash; Uptime monitoring that doesn't cry wolf.<br>
          <a href="https://uptrack.app" style="color: #7c3aed; text-decoration: none;">uptrack.app</a>
        </p>
      </div>
    </body>
    </html>
    """
  end

  defp text(greeting) do
    """
    Service Notice: Status Page Display Issue (Now Resolved)

    #{greeting}

    We're writing to let you know about a display issue that recently affected Uptrack status pages, including yours.

    WHAT HAPPENED

    For a period of time, status pages were incorrectly showing all monitors as "Unknown" instead of their actual status. This was caused by a bug in how the public status page read monitor data — it was querying the wrong data source and returning empty results instead of live check data.

    YOUR MONITORS WERE WORKING FINE

    The monitoring itself was not affected. Your websites were being checked on schedule throughout this period, and alerts would have fired normally for any real downtime. Only the public status page display was incorrect.

    WHAT WE DID

    We identified the root cause and deployed a fix. Your status page now correctly reflects the real-time status of all your monitors.

    We're sorry for any confusion this caused — especially if visitors to your status page were left uncertain about your services' availability.

    If you have any questions, reply to this email and we'll get back to you.

    — The Uptrack Team
    https://uptrack.app
    """
  end
end
