defmodule Uptrack.Billing.AddOnTest do
  use ExUnit.Case, async: true

  alias Uptrack.Billing.AddOn

  describe "valid_types/0" do
    test "returns 5 add-on types" do
      types = AddOn.valid_types()
      assert length(types) == 5
      assert "extra_monitors" in types
      assert "extra_fast_slots" in types
      assert "extra_teammates" in types
      assert "extra_sms" in types
      assert "extra_subscribers" in types
    end
  end

  describe "unit_price/1" do
    test "returns correct prices" do
      assert AddOn.unit_price("extra_monitors") == 20
      assert AddOn.unit_price("extra_fast_slots") == 100
      assert AddOn.unit_price("extra_teammates") == 500
      assert AddOn.unit_price("extra_sms") == 10
      assert AddOn.unit_price("extra_subscribers") == 1
    end

    test "returns 0 for unknown type" do
      assert AddOn.unit_price("nonexistent") == 0
    end
  end
end
