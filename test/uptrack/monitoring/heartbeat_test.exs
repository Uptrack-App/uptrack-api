defmodule Uptrack.Monitoring.HeartbeatTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring.Heartbeat

  import Uptrack.MonitoringFixtures

  describe "generate_token/0" do
    test "generates a URL-safe token" do
      token = Heartbeat.generate_token()
      assert is_binary(token)
      assert String.length(token) > 10
      # URL-safe base64 chars only
      assert String.match?(token, ~r/^[A-Za-z0-9_-]+$/)
    end

    test "generates unique tokens" do
      tokens = Enum.map(1..10, fn _ -> Heartbeat.generate_token() end)
      assert length(Enum.uniq(tokens)) == 10
    end
  end

  describe "record_heartbeat/1" do
    test "returns error for invalid token" do
      assert {:error, :not_found} = Heartbeat.record_heartbeat("nonexistent_token")
    end
  end
end
