defmodule Uptrack.Emails.InvitationEmailTest do
  use Uptrack.DataCase

  alias Uptrack.Emails.InvitationEmail
  alias Uptrack.Teams.TeamInvitation

  describe "invitation_email/3" do
    test "builds email with correct fields" do
      invitation = %TeamInvitation{
        email: "new-member@example.com",
        role: :editor,
        token: "test-token-123",
        expires_at: ~U[2026-03-01 00:00:00Z]
      }

      email = InvitationEmail.invitation_email(invitation, "Acme Inc.", "Jane Admin")

      assert email.to == [{"", "new-member@example.com"}]
      assert email.subject == "You've been invited to Acme Inc. on Uptrack"
      assert email.html_body =~ "Acme Inc."
      assert email.html_body =~ "Jane Admin"
      assert email.html_body =~ "Editor"
      assert email.html_body =~ "test-token-123"
      assert email.text_body =~ "Acme Inc."
      assert email.text_body =~ "Jane Admin"
    end

    test "formats role names with underscores" do
      invitation = %TeamInvitation{
        email: "user@example.com",
        role: :notify_only,
        token: "abc",
        expires_at: ~U[2026-03-01 00:00:00Z]
      }

      email = InvitationEmail.invitation_email(invitation, "Org", "Admin")

      assert email.html_body =~ "Notify only"
    end

    test "includes accept URL with app_url config" do
      invitation = %TeamInvitation{
        email: "user@example.com",
        role: :viewer,
        token: "my-unique-token",
        expires_at: ~U[2026-03-01 00:00:00Z]
      }

      email = InvitationEmail.invitation_email(invitation, "Org", "Admin")

      assert email.html_body =~ "/api/invitations/my-unique-token"
      assert email.text_body =~ "/api/invitations/my-unique-token"
    end
  end
end
