defmodule Uptrack.Monitoring.AlertChannel do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization

  @types ~w(email slack discord telegram)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "alert_channels" do
    field :type, :string
    field :name, :string
    field :config, :map
    field :is_active, :boolean, default: true

    belongs_to :organization, Organization
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(alert_channel, attrs) do
    alert_channel
    |> cast(attrs, [:type, :name, :config, :is_active, :organization_id, :user_id])
    |> validate_required([:type, :name, :config, :organization_id, :user_id])
    |> validate_inclusion(:type, @types)
    |> validate_config()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_config(changeset) do
    type = get_field(changeset, :type)
    config = get_field(changeset, :config)

    case {type, config} do
      {"email", %{"email" => email}} when is_binary(email) ->
        if String.contains?(email, "@") do
          changeset
        else
          add_error(changeset, :config, "email must be valid")
        end

      {"slack", %{"webhook_url" => url}} when is_binary(url) ->
        if String.starts_with?(url, "https://hooks.slack.com/") do
          changeset
        else
          add_error(changeset, :config, "webhook_url must be a valid Slack webhook URL")
        end

      {"discord", %{"webhook_url" => url}} when is_binary(url) ->
        if String.starts_with?(url, "https://discord.com/api/webhooks/") ||
             String.starts_with?(url, "https://discordapp.com/api/webhooks/") do
          changeset
        else
          add_error(changeset, :config, "webhook_url must be a valid Discord webhook URL")
        end

      {"telegram", %{"bot_token" => token, "chat_id" => chat_id}}
      when is_binary(token) and (is_binary(chat_id) or is_integer(chat_id)) ->
        changeset

      {nil, _} ->
        changeset

      _ ->
        add_error(changeset, :config, "invalid config for #{type} alert channel")
    end
  end

  def types, do: @types
end
