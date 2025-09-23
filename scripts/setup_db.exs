#!/usr/bin/env elixir

# Database setup script for multi-repo architecture
# This ensures all three schemas are created properly in deployment environments

Mix.install([
  {:postgrex, "~> 0.17"}
])

defmodule DBSetup do
  @moduledoc """
  Sets up all three database schemas for the multi-repo architecture.
  This handles the case where migrations are marked as "up" but schemas weren't created.
  """

  def run do
    IO.puts("Setting up multi-repo database schemas...")

    # Database connection config
    config = [
      hostname: System.get_env("DB_HOST", "localhost"),
      username: System.get_env("DB_USER", "postgres"),
      password: System.get_env("DB_PASSWORD", "postgres"),
      database: System.get_env("DB_NAME", "uptrack_dev"),
      port: String.to_integer(System.get_env("DB_PORT", "5432"))
    ]

    {:ok, conn} = Postgrex.start_link(config)

    try do
      # Create all three schemas
      create_schema(conn, "app")
      create_schema(conn, "oban")
      create_schema(conn, "results")

      IO.puts("✅ All schemas created successfully!")
      IO.puts("📋 You can now run: mix ecto.migrate")

    after
      Postgrex.close(conn)
    end
  end

  defp create_schema(conn, schema_name) do
    case Postgrex.query(conn, "CREATE SCHEMA IF NOT EXISTS #{schema_name}", []) do
      {:ok, _} ->
        IO.puts("  ✅ Schema '#{schema_name}' created")
      {:error, error} ->
        IO.puts("  ❌ Failed to create schema '#{schema_name}': #{inspect(error)}")
    end
  end
end

DBSetup.run()