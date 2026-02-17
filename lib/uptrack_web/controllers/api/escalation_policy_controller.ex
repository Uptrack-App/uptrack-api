defmodule UptrackWeb.Api.EscalationPolicyController do
  use UptrackWeb, :controller

  alias Uptrack.Escalation

  action_fallback UptrackWeb.Api.FallbackController

  def index(conn, _params) do
    org = conn.assigns.current_organization
    policies = Escalation.list_policies(org.id)
    render(conn, :index, policies: policies)
  end

  def show(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    case Escalation.get_organization_policy(org.id, id) do
      nil -> {:error, :not_found}
      policy -> render(conn, :show, policy: policy)
    end
  end

  def create(conn, params) do
    org = conn.assigns.current_organization

    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      "organization_id" => org.id
    }

    with {:ok, policy} <- Escalation.create_policy(attrs),
         {:ok, steps} <- maybe_replace_steps(policy.id, params["steps"]) do
      policy = %{policy | steps: steps || []}

      conn
      |> put_status(:created)
      |> render(:show, policy: policy)
    end
  end

  def update(conn, %{"id" => id} = params) do
    org = conn.assigns.current_organization

    with policy when not is_nil(policy) <- Escalation.get_organization_policy(org.id, id),
         {:ok, updated} <- Escalation.update_policy(policy, params),
         {:ok, steps} <- maybe_replace_steps(updated.id, params["steps"]) do
      updated = if steps, do: %{updated | steps: steps}, else: Uptrack.AppRepo.preload(updated, :steps)
      render(conn, :show, policy: updated)
    else
      nil -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete(conn, %{"id" => id}) do
    org = conn.assigns.current_organization

    with policy when not is_nil(policy) <- Escalation.get_organization_policy(org.id, id),
         {:ok, _} <- Escalation.delete_policy(policy) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_replace_steps(_policy_id, nil), do: {:ok, nil}

  defp maybe_replace_steps(policy_id, steps) when is_list(steps) do
    Escalation.replace_steps(policy_id, steps)
  end
end
