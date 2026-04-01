defmodule Uptrack.MCP.JsonRpc do
  @moduledoc "MCP JSON-RPC message builders."

  @protocol_version "2024-11-05"

  def protocol_version, do: @protocol_version

  def success_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  def tool_response(id, {:ok, content}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "content" => [%{"type" => "text", "text" => Jason.encode!(content)}],
        "structuredContent" => content,
        "isError" => false
      }
    }
  end

  def tool_response(id, {:error, reason}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "content" => [%{"type" => "text", "text" => reason}],
        "isError" => true
      }
    }
  end

  def error_response(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data, do: Map.put(error, "data", data), else: error
    %{"jsonrpc" => "2.0", "id" => id, "error" => error}
  end

  def define_tool(name, description, properties, required \\ [], opts \\ []) do
    schema = %{"type" => "object", "properties" => properties}
    schema = if required == [], do: schema, else: Map.put(schema, "required", required)

    tool = %{"name" => name, "description" => description, "inputSchema" => schema}

    annotations = build_annotations(opts)
    if map_size(annotations) > 0, do: Map.put(tool, "annotations", annotations), else: tool
  end

  defp build_annotations(opts) do
    Enum.reduce(opts, %{}, fn
      {:read_only, true}, acc -> Map.put(acc, "readOnlyHint", true)
      {:destructive, true}, acc -> Map.put(acc, "destructiveHint", true)
      _, acc -> acc
    end)
  end

  def prop(type, description), do: %{"type" => type, "description" => description}
end
