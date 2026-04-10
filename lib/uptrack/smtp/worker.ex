defmodule Uptrack.SMTP.Worker do
  @moduledoc """
  A GenServer that holds one persistent gen_smtp connection.

  Lifecycle:
  - On start: connects to primary SMTP host (localhost), falls back to secondary
  - When idle: registers in :pg group :smtp_idle_workers
  - When busy: leaves :pg group, delivers email, rejoins when done
  - After 60s idle: self-terminates (fleet scales down automatically)
  - On socket error: terminates (WorkerSupervisor will restart if needed)
  """

  use GenServer
  require Logger

  @pg_scope :smtp_workers
  @pg_group :idle
  @idle_timeout_ms 60_000

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def deliver(pid, email) do
    GenServer.call(pid, {:deliver, email}, 10_000)
  end

  # --- Callbacks ---

  @impl GenServer
  def init(_opts) do
    case open_connection() do
      {:ok, socket} ->
        :pg.join(@pg_scope, @pg_group, self())
        {:ok, %{socket: socket, idle_timer: schedule_idle_timeout()}}

      {:error, reason} ->
        Logger.error("[SMTPWorker] Failed to connect: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:deliver, email}, _from, %{socket: socket} = state) do
    :pg.leave(@pg_scope, @pg_group, self())
    cancel_idle_timer(state.idle_timer)

    {result, new_socket} = do_deliver(socket, email)

    case result do
      :ok ->
        :pg.join(@pg_scope, @pg_group, self())
        {:reply, :ok, %{state | socket: new_socket, idle_timer: schedule_idle_timeout()}}

      {:error, reason} ->
        # Socket is bad — terminate and let supervisor restart
        {:stop, {:smtp_error, reason}, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:idle_timeout, state) do
    Logger.debug("[SMTPWorker] Idle timeout — terminating")
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, %{socket: socket}) do
    :pg.leave(@pg_scope, @pg_group, self())
    try do
      smtp_client().close(socket)
    catch
      _, _ -> :ok
    end
  end

  # --- Private ---

  # Configurable via `config :uptrack, smtp_client: MyModule` — swap in tests.
  defp smtp_client, do: Application.get_env(:uptrack, :smtp_client, :gen_smtp_client)

  defp open_connection do
    primary = smtp_opts(:primary)
    case smtp_client().open(primary) do
      {:ok, socket} ->
        Logger.debug("[SMTPWorker] Connected to primary SMTP")
        {:ok, socket}

      {:error, reason} ->
        Logger.warning("[SMTPWorker] Primary SMTP failed (#{inspect(reason)}), trying fallback")
        fallback = smtp_opts(:fallback)
        case smtp_client().open(fallback) do
          {:ok, socket} ->
            Logger.info("[SMTPWorker] Connected to fallback SMTP")
            {:ok, socket}

          {:error, fallback_reason} ->
            {:error, fallback_reason}
        end
    end
  end

  defp do_deliver(socket, email) do
    from = elem(email.from, 1)
    to = Enum.map(email.to, &elem(&1, 1))
    body = render_mime(email)

    case smtp_client().deliver(socket, {from, to, body}) do
      {:ok, _receipt, new_socket} -> {:ok, new_socket}
      {:error, _type, message, new_socket} -> {{:error, message}, new_socket}
      {:error, reason} -> {{:error, reason}, socket}
    end
  end

  defp render_mime(%Swoosh.Email{} = email) do
    mail =
      Mail.build_multipart()
      |> Mail.put_subject(email.subject)
      |> Mail.put_from(email.from)
      |> put_recipients(:to, email.to)
      |> put_recipients(:cc, email.cc)
      |> put_recipients(:bcc, email.bcc)
      |> then(fn m -> if email.reply_to, do: Mail.put_reply_to(m, email.reply_to), else: m end)
      |> then(fn m -> if email.text_body, do: Mail.put_text(m, email.text_body), else: m end)
      |> then(fn m -> if email.html_body, do: Mail.put_html(m, email.html_body), else: m end)

    Mail.render(mail)
  end

  defp put_recipients(mail, _field, []), do: mail

  defp put_recipients(mail, :to, recipients) do
    Enum.reduce(recipients, mail, &Mail.put_to(&2, &1))
  end

  defp put_recipients(mail, :cc, recipients) do
    Enum.reduce(recipients, mail, &Mail.put_cc(&2, &1))
  end

  defp put_recipients(mail, :bcc, recipients) do
    Enum.reduce(recipients, mail, &Mail.put_bcc(&2, &1))
  end

  defp smtp_opts(:primary) do
    host = Application.get_env(:uptrack, :smtp_host, ~c"127.0.0.1")
    port = Application.get_env(:uptrack, :smtp_port, 587)
    build_opts(host, port)
  end

  defp smtp_opts(:fallback) do
    host = Application.get_env(:uptrack, :smtp_fallback_host, ~c"127.0.0.1")
    port = Application.get_env(:uptrack, :smtp_port, 587)
    build_opts(host, port)
  end

  defp build_opts(host, port) do
    username = Application.get_env(:uptrack, :smtp_username)
    password = Application.get_env(:uptrack, :smtp_password)

    base = [relay: host, port: port, tls: :never, auth: :if_available]

    if username && password do
      base ++ [username: username, password: password, auth: :always]
    else
      base
    end
  end

  defp schedule_idle_timeout do
    Process.send_after(self(), :idle_timeout, @idle_timeout_ms)
  end

  defp cancel_idle_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_idle_timer(_), do: :ok
end
