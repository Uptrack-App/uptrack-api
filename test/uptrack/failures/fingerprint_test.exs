defmodule Uptrack.Failures.FingerprintTest do
  use ExUnit.Case, async: true

  alias Uptrack.Failures.Fingerprint

  describe "compute/1" do
    test "produces a 3-tuple of {status_code, error_class, body_sha256}" do
      fp =
        Fingerprint.compute(%{
          status_code: 503,
          error_message: "upstream timed out",
          response_body: "<html>502 bad gateway</html>"
        })

      assert match?({503, :timeout, _hash}, fp)
    end

    test "nil body hashes to nil (not to sha256 of empty)" do
      assert {nil, :unknown, nil} =
               Fingerprint.compute(%{status_code: nil, error_message: nil, response_body: nil})
    end

    test "empty body hashes to nil too (collapse empty-body errors together)" do
      assert {500, :http, nil} =
               Fingerprint.compute(%{status_code: 500, error_message: nil, response_body: ""})
    end
  end

  describe "error_class/2" do
    test "timeout messages classify as :timeout" do
      assert Fingerprint.error_class("Request timed out after 30s", nil) == :timeout
      assert Fingerprint.error_class("timeout", 504) == :timeout
    end

    test "dns keywords classify as :dns" do
      assert Fingerprint.error_class("nxdomain: no such host", nil) == :dns
      assert Fingerprint.error_class("could not resolve foo.example", nil) == :dns
    end

    test "tcp-level errors classify as :tcp" do
      assert Fingerprint.error_class("connection refused", nil) == :tcp
      assert Fingerprint.error_class("econnrefused", nil) == :tcp
    end

    test "tls/ssl errors classify as :tls" do
      assert Fingerprint.error_class("tls handshake failure", nil) == :tls
      assert Fingerprint.error_class("certificate expired", nil) == :tls
    end

    test "assertion failures classify as :assertion" do
      assert Fingerprint.error_class("Assertion failed: status == 200", nil) == :assertion
    end

    test "unknown message with http status defaults to :http" do
      assert Fingerprint.error_class("something weird happened", nil) == :http
    end

    test "nil message with http status classifies as :http" do
      assert Fingerprint.error_class(nil, 503) == :http
    end

    test "nil message with nil status is :unknown" do
      assert Fingerprint.error_class(nil, nil) == :unknown
    end
  end

  describe "body_sha256/1" do
    test "produces 64-char lowercase hex for a non-empty body" do
      hash = Fingerprint.body_sha256("hello")
      assert byte_size(hash) == 64
      assert hash == String.downcase(hash)
      assert hash =~ ~r/^[0-9a-f]{64}$/
    end

    test "identical bodies hash identically" do
      assert Fingerprint.body_sha256("same") == Fingerprint.body_sha256("same")
    end

    test "different bodies hash differently" do
      refute Fingerprint.body_sha256("a") == Fingerprint.body_sha256("b")
    end
  end
end
