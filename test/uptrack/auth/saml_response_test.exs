defmodule Uptrack.Auth.SamlResponseTest do
  use ExUnit.Case, async: true

  alias Uptrack.Auth.SamlResponse

  defp make_assertion(attrs, subject_name \\ "user@example.com") do
    %Samly.Assertion{
      subject: %Samly.Subject{name: subject_name, name_qualifier: nil, sp_name_qualifier: nil, name_format: nil, confirmation_method: nil, notonorafter: nil},
      attributes: attrs,
      conditions: nil,
      authn: nil,
      idp_id: "test-idp",
      computed: %{}
    }
  end

  describe "extract_attributes/1" do
    test "extracts email from standard attribute" do
      assertion = make_assertion(%{"email" => "test@example.com"})
      result = SamlResponse.extract_attributes(assertion)

      assert result.email == "test@example.com"
    end

    test "extracts email from claims URI" do
      assertion = make_assertion(%{
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" => "claims@example.com"
      })
      result = SamlResponse.extract_attributes(assertion)

      assert result.email == "claims@example.com"
    end

    test "falls back to subject name for email" do
      assertion = make_assertion(%{}, "subject@example.com")
      result = SamlResponse.extract_attributes(assertion)

      assert result.email == "subject@example.com"
    end

    test "extracts display name" do
      assertion = make_assertion(%{"email" => "t@e.com", "displayName" => "Test User"})
      result = SamlResponse.extract_attributes(assertion)

      assert result.name == "Test User"
    end

    test "builds name from first + last" do
      assertion = make_assertion(%{"email" => "t@e.com", "firstName" => "Jane", "lastName" => "Doe"})
      result = SamlResponse.extract_attributes(assertion)

      assert result.name == "Jane Doe"
    end

    test "returns nil name when no name attributes" do
      assertion = make_assertion(%{"email" => "t@e.com"})
      result = SamlResponse.extract_attributes(assertion)

      assert result.name == nil
    end

    test "normalizes email to lowercase" do
      assertion = make_assertion(%{"email" => "  Test@EXAMPLE.COM  "})
      result = SamlResponse.extract_attributes(assertion)

      assert result.email == "test@example.com"
    end

    test "sets provider_id from subject" do
      assertion = make_assertion(%{"email" => "t@e.com"}, "unique-id-123")
      result = SamlResponse.extract_attributes(assertion)

      assert result.provider_id == "unique-id-123"
    end
  end
end
