defmodule Uptrack.SchemaVerifier do
  @moduledoc """
  Startup schema integrity check.

  Compares every Ecto schema's declared fields against the actual database
  columns using information_schema. Runs once at boot, before the HTTP endpoint
  starts. If any field is missing from the DB, the application refuses to start.

  This catches schema drift caused by Citus DDL operations (create_distributed_table,
  undistribute_table, alter_distributed_table) that can silently drop columns
  without touching the schema_migrations table.

  ## How it works in the supervision tree

  Returns `:ignore` on success (supervisor skips it, continues to next child).
  Raises on failure (supervisor fails to start, application does not boot).
  """

  require Logger

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary
    }
  end

  @doc false
  def start_link(_opts) do
    if Application.get_env(:uptrack, :verify_schema_on_boot, true) do
      verify!()
    end

    :ignore
  end

  @doc """
  Verifies all Ecto schemas match the database. Raises on mismatch.
  """
  def verify! do
    case verify() do
      :ok ->
        Logger.info("[SchemaVerifier] All #{length(app_schema_modules())} schemas verified OK")

      {:error, mismatches} ->
        message = format_error(mismatches)
        Logger.critical("[SchemaVerifier] #{message}")
        raise RuntimeError, message: message
    end
  end

  @doc """
  Returns `:ok` or `{:error, mismatches}` without raising.
  """
  def verify do
    mismatches =
      app_schema_modules()
      |> Enum.flat_map(&check_schema/1)

    if mismatches == [], do: :ok, else: {:error, mismatches}
  end

  # Discovers all Ecto schema modules in the :uptrack app that map to real DB tables.
  # Filters out embedded schemas (no prefix) and non-schema modules.
  defp app_schema_modules do
    {:ok, modules} = :application.get_key(:uptrack, :modules)

    Enum.filter(modules, fn mod ->
      function_exported?(mod, :__schema__, 1) and
        is_binary(mod.__schema__(:source)) and
        is_binary(mod.__schema__(:prefix))
    end)
  end

  defp check_schema(mod) do
    table = mod.__schema__(:source)
    prefix = mod.__schema__(:prefix)

    expected =
      mod.__schema__(:fields)
      |> Enum.map(&mod.__schema__(:field_source, &1))
      |> Enum.map(&Atom.to_string/1)

    actual = fetch_columns(prefix, table)
    missing = expected -- actual

    if missing == [], do: [], else: [{mod, "#{prefix}.#{table}", missing}]
  end

  defp fetch_columns(schema, table) do
    import Ecto.Query

    from(c in "columns",
      where: c.table_schema == ^schema and c.table_name == ^table,
      select: c.column_name,
      prefix: "information_schema"
    )
    |> Uptrack.AppRepo.all()
  rescue
    exception ->
      Logger.warning("[SchemaVerifier] Could not fetch columns for #{schema}.#{table}: #{Exception.message(exception)}")
      []
  end

  defp format_error(mismatches) do
    details =
      Enum.map_join(mismatches, "\n", fn {mod, table, cols} ->
        "  #{inspect(mod)} (#{table}): missing #{inspect(cols)}"
      end)

    """
    Schema mismatch — refusing to start.
    The following Ecto schema fields are missing from the database:

    #{details}

    This likely means a Citus DDL operation dropped columns without a migration.
    Fix: ALTER TABLE to restore the missing columns, then restart the service.
    """
  end
end
