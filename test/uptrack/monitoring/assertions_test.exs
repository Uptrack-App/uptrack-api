defmodule Uptrack.Monitoring.AssertionsTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.Assertions

  @json_body ~s({"status":"ok","data":{"count":42,"items":[{"id":1},{"id":2}]}})
  @html_body "<html><body>Service is healthy</body></html>"

  describe "evaluate/4" do
    test "returns :ok for empty assertions" do
      assert :ok = Assertions.evaluate([], 200, %{}, "")
    end

    test "returns :ok for nil assertions" do
      assert :ok = Assertions.evaluate(nil, 200, %{}, "")
    end
  end

  describe "json_path assertions" do
    test "simple field equals" do
      assertion = %{"type" => "json_path", "target" => "$.status", "operator" => "eq", "value" => "ok"}
      assert :ok = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end

    test "nested field equals" do
      assertion = %{"type" => "json_path", "target" => "$.data.count", "operator" => "eq", "value" => "42"}
      assert :ok = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end

    test "numeric greater than" do
      assertion = %{"type" => "json_path", "target" => "$.data.count", "operator" => "gt", "value" => "10"}
      assert :ok = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end

    test "numeric less than fails" do
      assertion = %{"type" => "json_path", "target" => "$.data.count", "operator" => "lt", "value" => "10"}
      assert {:error, _} = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end

    test "array index access" do
      assertion = %{"type" => "json_path", "target" => "$.data.items[0].id", "operator" => "eq", "value" => "1"}
      assert :ok = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end

    test "missing key returns error" do
      assertion = %{"type" => "json_path", "target" => "$.nonexistent", "operator" => "eq", "value" => "x"}
      assert {:error, msg} = Assertions.evaluate([assertion], 200, %{}, @json_body)
      assert msg =~ "not found"
    end

    test "non-json body returns error" do
      assertion = %{"type" => "json_path", "target" => "$.status", "operator" => "eq", "value" => "ok"}
      assert {:error, msg} = Assertions.evaluate([assertion], 200, %{}, @html_body)
      assert msg =~ "not valid JSON"
    end

    test "not equals" do
      assertion = %{"type" => "json_path", "target" => "$.status", "operator" => "neq", "value" => "error"}
      assert :ok = Assertions.evaluate([assertion], 200, %{}, @json_body)
    end
  end

  describe "header assertions" do
    test "header contains value" do
      headers = [{"content-type", "application/json; charset=utf-8"}]
      assertion = %{"type" => "header", "target" => "content-type", "operator" => "contains", "value" => "application/json"}
      assert :ok = Assertions.evaluate([assertion], 200, headers, "")
    end

    test "case-insensitive header matching" do
      headers = [{"Content-Type", "text/html"}]
      assertion = %{"type" => "header", "target" => "content-type", "operator" => "contains", "value" => "text/html"}
      assert :ok = Assertions.evaluate([assertion], 200, headers, "")
    end

    test "missing header returns error" do
      assertion = %{"type" => "header", "target" => "x-custom", "operator" => "eq", "value" => "test"}
      assert {:error, msg} = Assertions.evaluate([assertion], 200, [], "")
      assert msg =~ "not found"
    end
  end

  describe "status_code assertions" do
    test "status equals" do
      assertion = %{"type" => "status_code", "operator" => "eq", "value" => "200"}
      assert :ok = Assertions.evaluate([assertion], 200, [], "")
    end

    test "status not equals" do
      assertion = %{"type" => "status_code", "operator" => "eq", "value" => "200"}
      assert {:error, _} = Assertions.evaluate([assertion], 404, [], "")
    end
  end

  describe "regex assertions" do
    test "regex matches" do
      assertion = %{"type" => "regex", "target" => "status.*ok"}
      assert :ok = Assertions.evaluate([assertion], 200, [], @json_body)
    end

    test "regex does not match" do
      assertion = %{"type" => "regex", "target" => "error_code:\\d+"}
      assert {:error, msg} = Assertions.evaluate([assertion], 200, [], @json_body)
      assert msg =~ "did not match"
    end

    test "invalid regex returns error" do
      assertion = %{"type" => "regex", "target" => "[invalid"}
      assert {:error, msg} = Assertions.evaluate([assertion], 200, [], "test")
      assert msg =~ "Invalid regex"
    end
  end

  describe "contains / not_contains assertions" do
    test "contains passes when keyword present" do
      assertion = %{"type" => "contains", "target" => "healthy"}
      assert :ok = Assertions.evaluate([assertion], 200, [], @html_body)
    end

    test "contains fails when keyword absent" do
      assertion = %{"type" => "contains", "target" => "error"}
      assert {:error, _} = Assertions.evaluate([assertion], 200, [], @html_body)
    end

    test "not_contains passes when keyword absent" do
      assertion = %{"type" => "not_contains", "target" => "error"}
      assert :ok = Assertions.evaluate([assertion], 200, [], @html_body)
    end

    test "not_contains fails when keyword present" do
      assertion = %{"type" => "not_contains", "target" => "healthy"}
      assert {:error, _} = Assertions.evaluate([assertion], 200, [], @html_body)
    end
  end

  describe "multiple assertions (AND logic)" do
    test "all pass" do
      assertions = [
        %{"type" => "status_code", "operator" => "eq", "value" => "200"},
        %{"type" => "json_path", "target" => "$.status", "operator" => "eq", "value" => "ok"},
        %{"type" => "json_path", "target" => "$.data.count", "operator" => "gt", "value" => "0"}
      ]
      assert :ok = Assertions.evaluate(assertions, 200, [], @json_body)
    end

    test "first failure stops evaluation" do
      assertions = [
        %{"type" => "status_code", "operator" => "eq", "value" => "404"},
        %{"type" => "json_path", "target" => "$.status", "operator" => "eq", "value" => "ok"}
      ]
      assert {:error, msg} = Assertions.evaluate(assertions, 200, [], @json_body)
      assert msg =~ "Status code"
    end
  end

  describe "json_path_query/2" do
    test "root object" do
      assert {:ok, %{"a" => 1}} = Assertions.json_path_query(%{"a" => 1}, "$")
    end

    test "simple key" do
      assert {:ok, "hello"} = Assertions.json_path_query(%{"greeting" => "hello"}, "$.greeting")
    end

    test "nested keys" do
      data = %{"a" => %{"b" => %{"c" => 42}}}
      assert {:ok, 42} = Assertions.json_path_query(data, "$.a.b.c")
    end

    test "array index" do
      data = %{"items" => [10, 20, 30]}
      assert {:ok, 20} = Assertions.json_path_query(data, "$.items[1]")
    end

    test "parses JSON string body" do
      assert {:ok, "ok"} = Assertions.json_path_query(@json_body, "$.status")
    end
  end
end
