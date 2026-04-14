defmodule Uptrack.Admin do
  @moduledoc """
  Context for platform admin operations.

  Provides cross-organization user and organization search for internal staff.
  """
  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.AlertChannel

  @default_per_page 25
  @max_per_page 100

  @doc """
  Searches users across all organizations.

  Accepts a query string matched against name and email (case-insensitive).
  Returns paginated results with organization name joined.
  """
  def search_users(query_string, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = min(Keyword.get(opts, :per_page, @default_per_page), @max_per_page)
    offset = (page - 1) * per_page

    base =
      from u in User,
        join: o in Organization,
        on: o.id == u.organization_id,
        select: %{
          id: u.id,
          name: u.name,
          email: u.email,
          role: u.role,
          is_admin: u.is_admin,
          organization_id: u.organization_id,
          organization_name: o.name,
          inserted_at: u.inserted_at
        },
        order_by: [asc: u.email]

    filtered =
      if query_string && String.trim(query_string) != "" do
        pattern = "%#{String.trim(query_string)}%"

        where(
          base,
          [u, _o],
          ilike(u.email, ^pattern) or ilike(u.name, ^pattern)
        )
      else
        base
      end

    total = AppRepo.aggregate(filtered, :count)

    results =
      filtered
      |> limit(^per_page)
      |> offset(^offset)
      |> AppRepo.all()

    %{
      data: results,
      page: page,
      per_page: per_page,
      total: total
    }
  end

  @doc """
  Searches organizations across the platform.

  Accepts a query string matched against name (case-insensitive).
  Returns paginated results with member count.
  """
  def search_organizations(query_string, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = min(Keyword.get(opts, :per_page, @default_per_page), @max_per_page)
    offset = (page - 1) * per_page

    member_count_query =
      from u in User,
        group_by: u.organization_id,
        select: %{organization_id: u.organization_id, count: count(u.id)}

    base =
      from o in Organization,
        left_join: mc in subquery(member_count_query),
        on: mc.organization_id == o.id,
        select: %{
          id: o.id,
          name: o.name,
          slug: o.slug,
          plan: o.plan,
          member_count: coalesce(mc.count, 0),
          inserted_at: o.inserted_at
        },
        order_by: [asc: o.name]

    filtered =
      if query_string && String.trim(query_string) != "" do
        pattern = "%#{String.trim(query_string)}%"
        where(base, [o], ilike(o.name, ^pattern))
      else
        base
      end

    total = AppRepo.aggregate(filtered, :count)

    results =
      filtered
      |> limit(^per_page)
      |> offset(^offset)
      |> AppRepo.all()

    %{
      data: results,
      page: page,
      per_page: per_page,
      total: total
    }
  end

  @doc """
  Lists all alert channels across organizations with org name.
  Supports ILIKE search on channel name and org name.
  """
  def list_all_channels(query_string, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = min(Keyword.get(opts, :per_page, @default_per_page), @max_per_page)
    offset = (page - 1) * per_page

    base =
      from ac in AlertChannel,
        join: o in Organization,
        on: o.id == ac.organization_id,
        select: %{
          id: ac.id,
          name: ac.name,
          type: ac.type,
          is_active: ac.is_active,
          organization_id: ac.organization_id,
          organization_name: o.name,
          inserted_at: ac.inserted_at
        },
        order_by: [asc: o.name, asc: ac.name]

    filtered =
      if query_string && String.trim(query_string) != "" do
        pattern = "%#{String.trim(query_string)}%"

        where(
          base,
          [ac, o],
          ilike(ac.name, ^pattern) or ilike(o.name, ^pattern)
        )
      else
        base
      end

    total = AppRepo.aggregate(filtered, :count)

    results =
      filtered
      |> limit(^per_page)
      |> offset(^offset)
      |> AppRepo.all()

    %{data: results, page: page, per_page: per_page, total: total}
  end
end
