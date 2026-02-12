defmodule Uptrack.TeamsTest do
  use Uptrack.DataCase

  alias Uptrack.Teams
  alias Uptrack.Accounts.User
  import Uptrack.MonitoringFixtures
  import Uptrack.AccountsFixtures, except: [user_with_org_fixture: 0, user_with_org_fixture: 1]

  describe "list_members/1" do
    test "returns all members of an organization" do
      {user, org} = user_with_org_fixture()
      members = Teams.list_members(org.id)
      assert length(members) == 1
      assert hd(members).id == user.id
    end

    test "returns empty list for organization with no members" do
      assert Teams.list_members(Ecto.UUID.generate()) == []
    end
  end

  describe "get_member/2" do
    test "returns the member when found" do
      {user, org} = user_with_org_fixture()
      member = Teams.get_member(org.id, user.id)
      assert member.id == user.id
    end

    test "returns nil when member not in organization" do
      {_user, org} = user_with_org_fixture()
      assert Teams.get_member(org.id, Ecto.UUID.generate()) == nil
    end
  end

  describe "update_member_role/4" do
    test "updates a member's role" do
      {owner, org} = user_with_org_fixture()
      # Create a second user in the same org
      second_user = user_fixture(%{organization_id: org.id, role: :editor})

      assert {:ok, %User{role: :viewer}} =
               Teams.update_member_role(org.id, second_user.id, "viewer", owner.id)
    end

    test "prevents changing the last owner's role" do
      {owner, org} = user_with_org_fixture()

      assert {:error, _reason} =
               Teams.update_member_role(org.id, owner.id, "admin", owner.id)
    end
  end

  describe "remove_member/3" do
    test "removes a non-owner member" do
      {owner, org} = user_with_org_fixture()
      member = user_fixture(%{organization_id: org.id, role: :editor})

      assert {:ok, _} = Teams.remove_member(org.id, member.id, owner.id)
      assert Teams.get_member(org.id, member.id) == nil
    end

    test "prevents removing the last owner" do
      {owner, org} = user_with_org_fixture()
      assert {:error, _reason} = Teams.remove_member(org.id, owner.id, owner.id)
    end
  end

  describe "invite_member/4" do
    test "creates an invitation" do
      {owner, org} = user_with_org_fixture()

      assert {:ok, invitation} =
               Teams.invite_member(org.id, "new@example.com", "editor", owner.id)

      assert invitation.email == "new@example.com"
      assert invitation.role == :editor
      assert invitation.organization_id == org.id
    end

    test "prevents inviting existing member" do
      {owner, org} = user_with_org_fixture()

      assert {:error, _} =
               Teams.invite_member(org.id, owner.email, "editor", owner.id)
    end
  end

  describe "list_invitations/1" do
    test "returns pending invitations" do
      {owner, org} = user_with_org_fixture()
      {:ok, _inv} = Teams.invite_member(org.id, "pending@example.com", "viewer", owner.id)

      invitations = Teams.list_invitations(org.id)
      assert length(invitations) == 1
      assert hd(invitations).email == "pending@example.com"
    end
  end

  describe "cancel_invitation/2" do
    test "cancels a pending invitation" do
      {owner, org} = user_with_org_fixture()
      {:ok, inv} = Teams.invite_member(org.id, "cancel@example.com", "editor", owner.id)

      assert {:ok, _} = Teams.cancel_invitation(inv.id, owner.id)
      assert Teams.list_invitations(org.id) == []
    end
  end

  describe "audit logging" do
    test "log_action/6 creates an audit log entry" do
      {user, org} = user_with_org_fixture()

      assert {:ok, log} =
               Teams.log_action(org.id, user.id, "monitor.created", "monitor", Ecto.UUID.generate())

      assert log.action == "monitor.created"
      assert log.organization_id == org.id
      assert log.user_id == user.id
    end

    test "list_audit_logs/2 returns logs for organization" do
      {user, org} = user_with_org_fixture()
      Teams.log_action(org.id, user.id, "monitor.created", "monitor", Ecto.UUID.generate())
      Teams.log_action(org.id, user.id, "monitor.deleted", "monitor", Ecto.UUID.generate())

      logs = Teams.list_audit_logs(org.id)
      assert length(logs) >= 2
    end
  end
end
