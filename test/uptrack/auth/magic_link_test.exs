defmodule Uptrack.Auth.MagicLinkTest do
  use ExUnit.Case, async: true

  alias Uptrack.Auth.MagicLink

  describe "generate_token/0" do
    test "returns {raw, hashed} tuple" do
      {raw, hashed} = MagicLink.generate_token()
      assert is_binary(raw)
      assert is_binary(hashed)
      assert raw != hashed
    end

    test "generates unique tokens" do
      {raw1, _} = MagicLink.generate_token()
      {raw2, _} = MagicLink.generate_token()
      assert raw1 != raw2
    end
  end

  describe "hash_token/1" do
    test "produces consistent hash for same input" do
      assert MagicLink.hash_token("test") == MagicLink.hash_token("test")
    end

    test "produces different hash for different input" do
      assert MagicLink.hash_token("a") != MagicLink.hash_token("b")
    end
  end

  describe "valid_token?/2" do
    test "returns true for matching token" do
      {raw, hashed} = MagicLink.generate_token()
      assert MagicLink.valid_token?(raw, hashed)
    end

    test "returns false for wrong token" do
      {_raw, hashed} = MagicLink.generate_token()
      refute MagicLink.valid_token?("wrong-token", hashed)
    end
  end

  describe "expired?/1" do
    test "returns false for future expiry" do
      expires = DateTime.utc_now() |> DateTime.add(600, :second)
      refute MagicLink.expired?(%{expires_at: expires})
    end

    test "returns true for past expiry" do
      expires = DateTime.utc_now() |> DateTime.add(-600, :second)
      assert MagicLink.expired?(%{expires_at: expires})
    end
  end

  describe "used?/1" do
    test "returns false for nil used_at" do
      refute MagicLink.used?(%{used_at: nil})
    end

    test "returns true for non-nil used_at" do
      assert MagicLink.used?(%{used_at: DateTime.utc_now()})
    end
  end

  describe "name_from_email/1" do
    test "capitalizes simple email" do
      assert MagicLink.name_from_email("john@example.com") == "John"
    end

    test "splits on dots" do
      assert MagicLink.name_from_email("john.doe@example.com") == "John Doe"
    end

    test "splits on underscores and hyphens" do
      assert MagicLink.name_from_email("john_doe-smith@example.com") == "John Doe Smith"
    end
  end
end
