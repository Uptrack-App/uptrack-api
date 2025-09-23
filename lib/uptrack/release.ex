defmodule Uptrack.Release do
  @moduledoc """
  Production release tasks for Uptrack application.

  This module provides coordinated migration management for the multi-repo architecture.
  """

  @app :uptrack

  def migrate do
    load_app()

    # Migrate repos in dependency order to avoid foreign key issues
    migrate_repo(Uptrack.AppRepo)
    migrate_repo(Uptrack.ObanRepo)
    migrate_repo(Uptrack.ResultsRepo)

    IO.puts("✅ All repositories migrated successfully")
  end

  def migrate_repo(repo) do
    IO.puts("🔄 Migrating #{inspect(repo)}...")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
      Ecto.Migrator.run(repo, :up, all: true)
    end)

    IO.puts("✅ Completed migrating #{inspect(repo)}")
  end

  def rollback_repo(repo, version) do
    load_app()

    IO.puts("🔄 Rolling back #{inspect(repo)} to version #{version}...")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
      Ecto.Migrator.run(repo, :down, to: version)
    end)

    IO.puts("✅ Completed rollback of #{inspect(repo)}")
  end

  def migration_status do
    load_app()

    for repo <- repos() do
      IO.puts("📊 Migration status for #{inspect(repo)}:")

      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: false, log: :info)
      end)
    end
  end

  def verify_schemas do
    load_app()

    expected_schemas = ["app", "oban", "results"]

    {:ok, _, _} = Ecto.Migrator.with_repo(Uptrack.AppRepo, fn repo ->
      result = Ecto.Adapters.SQL.query!(repo, """
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name = ANY($1)
        ORDER BY schema_name
      """, [expected_schemas])

      found_schemas = Enum.map(result.rows, fn [schema] -> schema end)
      missing_schemas = expected_schemas -- found_schemas

      if missing_schemas == [] do
        IO.puts("✅ All required schemas exist: #{inspect(found_schemas)}")
      else
        IO.puts("❌ Missing schemas: #{inspect(missing_schemas)}")
        IO.puts("   Found schemas: #{inspect(found_schemas)}")
      end
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end