defmodule Uptrack.AppRepo.Migrations.UpdateRegionNames do
  use Ecto.Migration

  def up do
    execute """
    UPDATE app.regions SET name = 'Europe (Nuremberg, Germany)', updated_at = NOW() WHERE code = 'eu-north-1'
    """

    execute """
    UPDATE app.regions SET name = 'Americas (Ashburn)', updated_at = NOW() WHERE code = 'us-west-2'
    """

    execute """
    UPDATE app.regions SET name = 'Asia (Hyderabad, India)', updated_at = NOW() WHERE code = 'ap-southeast-1'
    """
  end

  def down do
    execute """
    UPDATE app.regions SET name = 'Europe (Helsinki)', updated_at = NOW() WHERE code = 'eu-north-1'
    """

    execute """
    UPDATE app.regions SET name = 'US West (Oregon)', updated_at = NOW() WHERE code = 'us-west-2'
    """

    execute """
    UPDATE app.regions SET name = 'Asia Pacific (Singapore)', updated_at = NOW() WHERE code = 'ap-southeast-1'
    """
  end
end
