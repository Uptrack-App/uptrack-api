defmodule UptrackWeb.Api.EscalationPolicyJSON do
  alias Uptrack.Escalation.{EscalationPolicy, EscalationStep}

  def index(%{policies: policies}) do
    %{data: Enum.map(policies, &data/1)}
  end

  def show(%{policy: policy}) do
    %{data: data(policy)}
  end

  defp data(%EscalationPolicy{} = p) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      organization_id: p.organization_id,
      steps: Enum.map(p.steps || [], &step_data/1),
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end

  defp step_data(%EscalationStep{} = s) do
    %{
      id: s.id,
      step_order: s.step_order,
      delay_minutes: s.delay_minutes,
      alert_channel_id: s.alert_channel_id
    }
  end
end
