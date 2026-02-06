defmodule Uptrack.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{Monitor, AlertChannel, StatusPage}

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @roles ~w(owner admin editor viewer notify_only)a

  @schema_prefix "app"
  schema "users" do
    field :email, :string
    field :provider, :string
    field :provider_id, :string
    field :name, :string
    field :hashed_password, :string
    field :password, :string, virtual: true
    field :confirmed_at, :naive_datetime
    field :notification_preferences, :map, default: %{}
    field :role, Ecto.Enum, values: @roles, default: :owner

    belongs_to :organization, Organization
    has_many :monitors, Monitor
    has_many :alert_channels, AlertChannel
    has_many :status_pages, StatusPage

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the list of valid roles.
  """
  def roles, do: @roles

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :provider,
      :provider_id,
      :name,
      :hashed_password,
      :confirmed_at,
      :notification_preferences,
      :organization_id,
      :role
    ])
    |> validate_required([:email, :name])
    |> validate_email()
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
    |> ensure_notification_preferences()
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:organization_id])
    |> validate_password(hash_password: true)
    |> foreign_key_constraint(:organization_id)
  end

  def oauth_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> validate_required([:provider, :provider_id, :organization_id])
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Returns a changeset for updating notification preferences.
  """
  def notification_preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:notification_preferences])
    |> validate_notification_preferences()
  end

  @doc """
  Returns the default notification preferences.
  """
  def default_notification_preferences do
    %{
      "email_enabled" => true,
      "email_on_incident_started" => true,
      "email_on_incident_resolved" => true,
      "email_on_monitor_down" => true,
      "email_on_monitor_up" => true,
      "notification_frequency" => "immediate",
      "quiet_hours_enabled" => false,
      "quiet_hours_start" => "22:00",
      "quiet_hours_end" => "08:00",
      "quiet_hours_timezone" => "UTC",
      "send_ssl_expiry_alerts" => true,
      "ssl_expiry_days_before" => 30,
      "weekly_summary_enabled" => true,
      "monthly_summary_enabled" => true,
      "escalation_enabled" => false,
      "escalation_delay_minutes" => 30
    }
  end

  @doc """
  Gets a user's notification preferences with defaults merged.
  """
  def get_notification_preferences(user) do
    defaults = default_notification_preferences()
    user_prefs = user.notification_preferences || %{}
    Map.merge(defaults, user_prefs)
  end

  @doc """
  Checks if a user should receive a specific type of notification.
  """
  def should_notify?(user, notification_type) do
    prefs = get_notification_preferences(user)

    case notification_type do
      :incident_started -> prefs["email_enabled"] && prefs["email_on_incident_started"]
      :incident_resolved -> prefs["email_enabled"] && prefs["email_on_incident_resolved"]
      :monitor_down -> prefs["email_enabled"] && prefs["email_on_monitor_down"]
      :monitor_up -> prefs["email_enabled"] && prefs["email_on_monitor_up"]
      :ssl_expiry -> prefs["email_enabled"] && prefs["send_ssl_expiry_alerts"]
      _ -> false
    end
  end

  defp ensure_notification_preferences(changeset) do
    case get_field(changeset, :notification_preferences) do
      nil ->
        put_change(changeset, :notification_preferences, default_notification_preferences())

      prefs when is_map(prefs) ->
        merged_prefs = Map.merge(default_notification_preferences(), prefs)
        put_change(changeset, :notification_preferences, merged_prefs)

      _ ->
        changeset
    end
  end

  defp validate_notification_preferences(changeset) do
    prefs = get_change(changeset, :notification_preferences)

    if prefs do
      changeset
      |> validate_frequency(prefs)
      |> validate_quiet_hours(prefs)
      |> validate_escalation(prefs)
    else
      changeset
    end
  end

  defp validate_frequency(changeset, prefs) do
    valid_frequencies = ["immediate", "hourly", "daily"]
    frequency = prefs["notification_frequency"]

    if frequency in valid_frequencies do
      changeset
    else
      add_error(changeset, :notification_preferences, "invalid notification frequency")
    end
  end

  defp validate_quiet_hours(changeset, prefs) do
    if prefs["quiet_hours_enabled"] do
      start_time = prefs["quiet_hours_start"]
      end_time = prefs["quiet_hours_end"]

      if valid_time_format?(start_time) && valid_time_format?(end_time) do
        changeset
      else
        add_error(changeset, :notification_preferences, "invalid quiet hours format")
      end
    else
      changeset
    end
  end

  defp validate_escalation(changeset, prefs) do
    if prefs["escalation_enabled"] do
      delay = prefs["escalation_delay_minutes"]

      if is_integer(delay) && delay > 0 do
        changeset
      else
        add_error(
          changeset,
          :notification_preferences,
          "escalation delay must be a positive integer"
        )
      end
    else
      changeset
    end
  end

  defp valid_time_format?(time) when is_binary(time) do
    case Regex.match?(~r/^\d{2}:\d{2}$/, time) do
      true ->
        [hour, minute] = String.split(time, ":")
        hour = String.to_integer(hour)
        minute = String.to_integer(minute)
        hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59

      false ->
        false
    end
  end

  defp valid_time_format?(_), do: false

  # Role hierarchy helpers

  @doc """
  Returns true if the user has at least the given role level.
  Role hierarchy: owner > admin > editor > viewer > notify_only
  """
  def has_role_at_least?(user, required_role) do
    role_level(user.role) >= role_level(required_role)
  end

  @doc """
  Returns true if the user can manage team members (owner or admin).
  """
  def can_manage_team?(user) do
    user.role in [:owner, :admin]
  end

  @doc """
  Returns true if the user can create/edit resources (owner, admin, or editor).
  """
  def can_edit?(user) do
    user.role in [:owner, :admin, :editor]
  end

  @doc """
  Returns true if the user can access the dashboard (everyone except notify_only).
  """
  def can_access_dashboard?(user) do
    user.role != :notify_only
  end

  @doc """
  Returns true if the user is the organization owner.
  """
  def is_owner?(user) do
    user.role == :owner
  end

  defp role_level(:owner), do: 5
  defp role_level(:admin), do: 4
  defp role_level(:editor), do: 3
  defp role_level(:viewer), do: 2
  defp role_level(:notify_only), do: 1
  defp role_level(_), do: 0
end
