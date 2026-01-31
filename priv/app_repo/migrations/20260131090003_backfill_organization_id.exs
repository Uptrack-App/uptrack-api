defmodule Uptrack.AppRepo.Migrations.BackfillOrganizationId do
  use Ecto.Migration

  def up do
    # Create a default organization for each existing user
    # The org name is the user's name, slug is derived from email
    execute """
    INSERT INTO app.organizations (id, name, slug, plan, settings, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      COALESCE(name, split_part(email, '@', 1)),
      LOWER(REPLACE(REPLACE(email, '@', '-at-'), '.', '-')),
      'free',
      '{}',
      NOW(),
      NOW()
    FROM app.users
    WHERE NOT EXISTS (
      SELECT 1 FROM app.organizations WHERE slug = LOWER(REPLACE(REPLACE(app.users.email, '@', '-at-'), '.', '-'))
    )
    """

    # Update users with their organization_id
    execute """
    UPDATE app.users u
    SET organization_id = o.id
    FROM app.organizations o
    WHERE o.slug = LOWER(REPLACE(REPLACE(u.email, '@', '-at-'), '.', '-'))
      AND u.organization_id IS NULL
    """

    # Update monitors with organization_id from their user
    execute """
    UPDATE app.monitors m
    SET organization_id = u.organization_id
    FROM app.users u
    WHERE m.user_id = u.id
      AND m.organization_id IS NULL
    """

    # Update alert_channels with organization_id from their user
    execute """
    UPDATE app.alert_channels ac
    SET organization_id = u.organization_id
    FROM app.users u
    WHERE ac.user_id = u.id
      AND ac.organization_id IS NULL
    """

    # Update status_pages with organization_id from their user
    execute """
    UPDATE app.status_pages sp
    SET organization_id = u.organization_id
    FROM app.users u
    WHERE sp.user_id = u.id
      AND sp.organization_id IS NULL
    """

    # Update incidents with organization_id from their monitor's user
    execute """
    UPDATE app.incidents i
    SET organization_id = u.organization_id
    FROM app.monitors m
    JOIN app.users u ON m.user_id = u.id
    WHERE i.monitor_id = m.id
      AND i.organization_id IS NULL
    """
  end

  def down do
    # Clear organization_id from all tables (reverse the backfill)
    execute "UPDATE app.incidents SET organization_id = NULL"
    execute "UPDATE app.status_pages SET organization_id = NULL"
    execute "UPDATE app.alert_channels SET organization_id = NULL"
    execute "UPDATE app.monitors SET organization_id = NULL"
    execute "UPDATE app.users SET organization_id = NULL"

    # Delete auto-created organizations
    execute "DELETE FROM app.organizations"
  end
end
