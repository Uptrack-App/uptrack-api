defmodule UptrackWeb.Api.AddOnController do
  use UptrackWeb, :controller

  alias Uptrack.Billing
  alias Uptrack.Billing.AddOn

  @doc "GET /api/billing/add-ons — list all add-ons for the org."
  def index(conn, _params) do
    org = conn.assigns.current_organization

    if org.plan == "free" do
      conn
      |> put_status(402)
      |> json(%{error: %{message: "Add-ons require a paid plan."}})
    else
      add_ons = Billing.list_add_ons(org.id)
      monthly_cost = Billing.add_on_monthly_cost(org.id)

      json(conn, %{
        data: Enum.map(add_ons, fn a ->
          %{type: a.type, quantity: a.quantity, unit_price_cents: AddOn.unit_price(a.type)}
        end),
        monthly_cost_cents: monthly_cost,
        available_types: Enum.map(AddOn.valid_types(), fn t ->
          %{type: t, unit_price_cents: AddOn.unit_price(t)}
        end)
      })
    end
  end

  @doc "POST /api/billing/add-ons — set add-on quantity."
  def update(conn, %{"type" => type, "quantity" => quantity}) when is_integer(quantity) do
    org = conn.assigns.current_organization

    if org.plan == "free" do
      conn
      |> put_status(402)
      |> json(%{error: %{message: "Add-ons require a paid plan."}})
    else
      case Billing.set_add_on(org.id, type, quantity) do
        {:ok, _} ->
          json(conn, %{ok: true, monthly_cost_cents: Billing.add_on_monthly_cost(org.id)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def update(conn, %{"type" => type, "quantity" => quantity}) when is_binary(quantity) do
    case Integer.parse(quantity) do
      {q, _} -> update(conn, %{"type" => type, "quantity" => q})
      :error ->
        conn |> put_status(400) |> json(%{error: %{message: "Quantity must be a number."}})
    end
  end
end
