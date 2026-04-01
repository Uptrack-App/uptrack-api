defmodule Uptrack.OAuth.Tokens do
  @moduledoc """
  Token resource and subject management for RFC 8707/9068.

  Pure database operations — no business logic.
  """

  import Ecto.Query

  alias Uptrack.AppRepo

  @doc "Sets the resource field (RFC 8707) on a token."
  def set_token_resource(token_value, resource)
      when is_binary(token_value) and is_binary(resource) do
    {count, _} =
      from(t in "oauth_tokens", where: t.value == ^token_value, update: [set: [resource: ^resource]])
      |> AppRepo.update_all([])

    {:ok, count}
  end

  @doc "Sets the sub (subject) claim on a token. Format: org:{id}"
  def set_token_sub(token_value, sub) when is_binary(token_value) and is_binary(sub) do
    {count, _} =
      from(t in "oauth_tokens", where: t.value == ^token_value, update: [set: [sub: ^sub]])
      |> AppRepo.update_all([])

    {:ok, count}
  end

  @doc "Gets the sub claim for a token."
  def get_token_sub(token_value) when is_binary(token_value) do
    from(t in "oauth_tokens", where: t.value == ^token_value, select: t.sub)
    |> AppRepo.one()
  end

  @doc "Extracts organization ID from a sub claim like 'org:abc-123'."
  def extract_org_id("org:" <> org_id), do: {:ok, org_id}
  def extract_org_id(nil), do: {:error, :missing_sub}
  def extract_org_id(_), do: {:error, :invalid_sub_format}
end
