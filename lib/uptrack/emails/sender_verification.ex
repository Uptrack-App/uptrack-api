defmodule Uptrack.Emails.SenderVerification do
  @moduledoc """
  Pure module — builds verification email content.
  No database calls, no side effects.
  """

  import Swoosh.Email

  alias Uptrack.Mailer

  @from {"Uptrack", "noreply@uptrack.app"}

  def send_verification(sender) do
    verify_url = "#{app_url()}/api/custom-sender/verify/#{sender.verification_token}"

    email =
      new()
      |> to({sender.sender_name, sender.sender_email})
      |> from(@from)
      |> subject("Verify your custom sender email — Uptrack")
      |> html_body("""
      <div style="font-family:sans-serif;max-width:500px;margin:0 auto">
        <h2>Verify your sender email</h2>
        <p>You requested to use <strong>#{sender.sender_email}</strong> as a custom sender for Uptrack alerts.</p>
        <p><a href="#{verify_url}" style="display:inline-block;padding:12px 24px;background:#7553FF;color:white;text-decoration:none;border-radius:6px">Verify Email</a></p>
        <p style="color:#888;font-size:13px">If you didn't request this, ignore this email.</p>
      </div>
      """)
      |> text_body("Verify your sender email: #{verify_url}")

    Mailer.deliver(email)
  end

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")
end
