defmodule Uptrack.Emails.CustomSendersTest do
  use Uptrack.DataCase

  alias Uptrack.Emails.CustomSenders

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  describe "setup_sender/3" do
    test "creates a sender with verification pending" do
      org = organization_fixture(plan: "business")

      assert {:ok, sender} = CustomSenders.setup_sender(org.id, "My Company", "alerts@mycompany.com")
      assert sender.sender_name == "My Company"
      assert sender.sender_email == "alerts@mycompany.com"
      assert sender.verified == false
    end

    test "updates existing sender" do
      org = organization_fixture(plan: "business")

      CustomSenders.setup_sender(org.id, "Old Name", "old@example.com")
      {:ok, updated} = CustomSenders.setup_sender(org.id, "New Name", "new@example.com")

      assert updated.sender_name == "New Name"
      assert updated.sender_email == "new@example.com"
    end
  end

  describe "verify_token/1" do
    test "verifies a valid token" do
      org = organization_fixture(plan: "business")
      {:ok, sender} = CustomSenders.setup_sender(org.id, "Test", "test@test.com")

      # Get the token from DB
      db_sender = CustomSenders.get_sender(org.id)

      assert {:ok, verified} = CustomSenders.verify_token(db_sender.verification_token)
      assert verified.verified == true
    end

    test "rejects invalid token" do
      assert {:error, :invalid_token} = CustomSenders.verify_token("bogus-token")
    end
  end

  describe "sender_for/1" do
    test "returns default when no custom sender" do
      org = organization_fixture()
      assert {"Uptrack", "alerts@uptrack.app"} = CustomSenders.sender_for(org.id)
    end

    test "returns custom sender when verified" do
      org = organization_fixture(plan: "business")
      {:ok, _} = CustomSenders.setup_sender(org.id, "Custom", "custom@test.com")

      # Verify it
      db_sender = CustomSenders.get_sender(org.id)
      CustomSenders.verify_token(db_sender.verification_token)

      assert {"Custom", "custom@test.com"} = CustomSenders.sender_for(org.id)
    end

    test "returns default when custom sender unverified" do
      org = organization_fixture(plan: "business")
      CustomSenders.setup_sender(org.id, "Unverified", "unverified@test.com")

      assert {"Uptrack", "alerts@uptrack.app"} = CustomSenders.sender_for(org.id)
    end
  end

  describe "delete_sender/1" do
    test "deletes existing sender" do
      org = organization_fixture(plan: "business")
      CustomSenders.setup_sender(org.id, "Del", "del@test.com")

      assert {:ok, _} = CustomSenders.delete_sender(org.id)
      assert CustomSenders.get_sender(org.id) == nil
    end

    test "returns error when no sender" do
      org = organization_fixture()
      assert {:error, :not_found} = CustomSenders.delete_sender(org.id)
    end
  end
end
