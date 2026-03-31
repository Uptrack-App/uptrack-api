defmodule Uptrack.Integrations.OAuthStateTest do
  use ExUnit.Case

  alias Uptrack.Integrations.OAuthState

  # OAuthState GenServer is already started by the application

  describe "store/2 and get_and_delete/1" do
    test "stores and retrieves state data" do
      state = "test_state_#{System.unique_integer([:positive])}"
      data = %{organization_id: "org_123", provider: :slack}

      assert :ok = OAuthState.store(state, data)
      assert OAuthState.get_and_delete(state) == data
    end

    test "returns nil for unknown state" do
      assert OAuthState.get_and_delete("nonexistent_state") == nil
    end

    test "state is single-use (deleted after get)" do
      state = "single_use_#{System.unique_integer([:positive])}"
      OAuthState.store(state, %{test: true})

      assert OAuthState.get_and_delete(state) == %{test: true}
      assert OAuthState.get_and_delete(state) == nil
    end

    test "stores multiple states independently" do
      state1 = "multi_1_#{System.unique_integer([:positive])}"
      state2 = "multi_2_#{System.unique_integer([:positive])}"

      OAuthState.store(state1, %{id: 1})
      OAuthState.store(state2, %{id: 2})

      assert OAuthState.get_and_delete(state1) == %{id: 1}
      assert OAuthState.get_and_delete(state2) == %{id: 2}
    end
  end
end
