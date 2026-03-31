defmodule Uptrack.Monitoring.SmartDefaultsTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.SmartDefaults

  describe "from_url/1" do
    test "detects HTTP monitor type for web URLs" do
      defaults = SmartDefaults.from_url("https://example.com")
      assert defaults.monitor_type == "http"
    end

    test "detects HTTP for URLs without scheme" do
      defaults = SmartDefaults.from_url("example.com")
      assert defaults.monitor_type == "http"
    end

    test "generates name from domain" do
      defaults = SmartDefaults.from_url("https://api.example.com/health")
      assert defaults.name =~ "example"
    end

    test "sets default interval" do
      defaults = SmartDefaults.from_url("https://example.com")
      assert is_integer(defaults.interval)
      assert defaults.interval > 0
    end

    test "handles empty URL" do
      defaults = SmartDefaults.from_url("")
      assert is_map(defaults)
    end

    test "handles nil URL with guard" do
      # SmartDefaults.from_url/1 has a guard `when is_binary(url)` so nil raises FunctionClauseError
      assert_raise FunctionClauseError, fn -> SmartDefaults.from_url(nil) end
    end
  end

  describe "suggest_regions/1" do
    test "returns a list of regions" do
      regions = SmartDefaults.suggest_regions(nil)
      assert is_list(regions)
    end

    test "returns regions for a timezone" do
      regions = SmartDefaults.suggest_regions("America/New_York")
      assert is_list(regions)
    end
  end
end
