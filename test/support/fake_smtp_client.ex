defmodule Uptrack.SMTP.FakeSMTPState do
  @moduledoc "Shared state for FakeSMTPClient — readable across processes in tests."
  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def set_open_result(result), do: Agent.update(__MODULE__, &Map.put(&1, :open, result))
  def set_deliver_result(result), do: Agent.update(__MODULE__, &Map.put(&1, :deliver, result))
  def reset, do: Agent.update(__MODULE__, fn _ -> %{} end)

  def open_result, do: Agent.get(__MODULE__, &Map.get(&1, :open))
  def deliver_result, do: Agent.get(__MODULE__, &Map.get(&1, :deliver))
end

defmodule Uptrack.SMTP.FakeSMTPClient do
  @moduledoc "Test double for :gen_smtp_client."

  alias Uptrack.SMTP.FakeSMTPState

  def open(_opts) do
    case FakeSMTPState.open_result() do
      nil -> {:ok, :fake_socket}
      result -> result
    end
  end

  def deliver(socket, {_from, _to, _body}) do
    case FakeSMTPState.deliver_result() do
      nil -> {:ok, "250 OK", socket}
      result -> result
    end
  end

  def close(_socket), do: :ok
end
