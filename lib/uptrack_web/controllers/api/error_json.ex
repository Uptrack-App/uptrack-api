defmodule UptrackWeb.Api.ErrorJSON do
  @moduledoc """
  JSON error responses for API endpoints.
  """

  def render("error.json", %{changeset: changeset}) do
    errors = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)

    %{
      error: %{
        message: "Validation failed",
        details: errors
      }
    }
  end

  def render("error.json", %{message: message}) do
    %{
      error: %{
        message: message
      }
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
