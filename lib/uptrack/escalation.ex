defmodule Uptrack.Escalation do
  @moduledoc """
  Context for escalation policy management and execution.
  """

  import Ecto.Query
  alias Uptrack.AppRepo
  alias Uptrack.Escalation.{EscalationPolicy, EscalationStep}

  # --------------------------------------------------------------------------
  # CRUD
  # --------------------------------------------------------------------------

  def list_policies(organization_id) do
    EscalationPolicy
    |> where([p], p.organization_id == ^organization_id)
    |> preload(:steps)
    |> AppRepo.all()
  end

  def get_policy(id) do
    EscalationPolicy
    |> AppRepo.get(id)
    |> AppRepo.preload(:steps)
  end

  def get_organization_policy(organization_id, id) do
    EscalationPolicy
    |> where([p], p.organization_id == ^organization_id and p.id == ^id)
    |> preload(:steps)
    |> AppRepo.one()
  end

  def create_policy(attrs) do
    %EscalationPolicy{}
    |> EscalationPolicy.changeset(attrs)
    |> AppRepo.insert()
  end

  def update_policy(%EscalationPolicy{} = policy, attrs) do
    policy
    |> EscalationPolicy.changeset(attrs)
    |> AppRepo.update()
  end

  def delete_policy(%EscalationPolicy{} = policy) do
    AppRepo.delete(policy)
  end

  # --------------------------------------------------------------------------
  # Steps
  # --------------------------------------------------------------------------

  def add_step(attrs) do
    %EscalationStep{}
    |> EscalationStep.changeset(attrs)
    |> AppRepo.insert()
  end

  def remove_step(step_id) do
    case AppRepo.get(EscalationStep, step_id) do
      nil -> {:error, :not_found}
      step -> AppRepo.delete(step)
    end
  end

  def replace_steps(policy_id, steps_attrs) when is_list(steps_attrs) do
    AppRepo.transaction(fn ->
      # Delete existing steps
      from(s in EscalationStep, where: s.escalation_policy_id == ^policy_id)
      |> AppRepo.delete_all()

      # Insert new steps
      steps_attrs
      |> Enum.with_index(1)
      |> Enum.map(fn {step_attrs, order} ->
        attrs =
          step_attrs
          |> Map.put("escalation_policy_id", policy_id)
          |> Map.put("step_order", Map.get(step_attrs, "step_order", order))

        case add_step(attrs) do
          {:ok, step} -> step
          {:error, changeset} -> AppRepo.rollback(changeset)
        end
      end)
    end)
  end

  # --------------------------------------------------------------------------
  # Escalation execution
  # --------------------------------------------------------------------------

  @doc """
  Gets the escalation policy for a monitor, if any.
  Returns nil if the monitor has no policy assigned.
  """
  def get_monitor_policy(monitor) do
    case monitor.escalation_policy_id do
      nil -> nil
      policy_id -> get_policy(policy_id)
    end
  end

  @doc """
  Gets steps for a specific escalation level (step_order).
  """
  def get_steps_for_order(policy_id, step_order) do
    EscalationStep
    |> where([s], s.escalation_policy_id == ^policy_id and s.step_order == ^step_order)
    |> preload(:alert_channel)
    |> AppRepo.all()
  end

  @doc """
  Gets the maximum step order for a policy.
  """
  def max_step_order(policy_id) do
    EscalationStep
    |> where([s], s.escalation_policy_id == ^policy_id)
    |> select([s], max(s.step_order))
    |> AppRepo.one() || 0
  end
end
