defmodule Uptrack.AppRepo.Migrations.AddErrorTracker do
  use Ecto.Migration

  def up, do: ErrorTracker.Migration.up(create_schema: false)
  def down, do: ErrorTracker.Migration.down()
end
