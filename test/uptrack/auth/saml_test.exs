defmodule Uptrack.Auth.SamlTest do
  use Uptrack.DataCase

  alias Uptrack.Auth.Saml

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  describe "configure/2" do
    test "creates SSO provider" do
      org = organization_fixture(plan: "business")

      assert {:ok, provider} = Saml.configure(org.id, %{
        entity_id: "https://idp.example.com",
        sso_url: "https://idp.example.com/sso",
        certificate: "-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----"
      })

      assert provider.entity_id == "https://idp.example.com"
      assert provider.organization_id == org.id
    end

    test "updates existing provider" do
      org = organization_fixture(plan: "business")

      {:ok, _} = Saml.configure(org.id, %{
        entity_id: "https://idp.example.com",
        sso_url: "https://idp.example.com/sso",
        certificate: "cert1"
      })

      {:ok, updated} = Saml.configure(org.id, %{
        sso_url: "https://idp.example.com/sso-v2"
      })

      assert updated.sso_url == "https://idp.example.com/sso-v2"
    end
  end

  describe "sso_configured?/1 and sso_enforced?/1" do
    test "returns false when no provider" do
      org = organization_fixture()
      refute Saml.sso_configured?(org.id)
      refute Saml.sso_enforced?(org.id)
    end

    test "returns true when provider exists" do
      org = organization_fixture(plan: "business")
      Saml.configure(org.id, %{
        entity_id: "https://idp.test.com",
        sso_url: "https://idp.test.com/sso",
        certificate: "cert"
      })

      assert Saml.sso_configured?(org.id)
      refute Saml.sso_enforced?(org.id)
    end

    test "enforced when enforce=true" do
      org = organization_fixture(plan: "business")
      Saml.configure(org.id, %{
        entity_id: "https://idp.enforce.com",
        sso_url: "https://idp.enforce.com/sso",
        certificate: "cert",
        enforce: true
      })

      assert Saml.sso_enforced?(org.id)
    end
  end

  describe "delete_provider/1" do
    test "deletes existing provider" do
      org = organization_fixture(plan: "business")
      Saml.configure(org.id, %{
        entity_id: "https://idp.del.com",
        sso_url: "https://idp.del.com/sso",
        certificate: "cert"
      })

      assert {:ok, _} = Saml.delete_provider(org.id)
      refute Saml.sso_configured?(org.id)
    end

    test "returns error when no provider" do
      org = organization_fixture()
      assert {:error, :not_found} = Saml.delete_provider(org.id)
    end
  end
end
