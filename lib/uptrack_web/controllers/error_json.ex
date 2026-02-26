defmodule UptrackWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)

    %{error: %{message: message}}
  end
end
