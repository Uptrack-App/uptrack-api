defmodule Mix.Tasks.SendApologyEmail do
  @moduledoc """
  Sends the status page apology email to all users who have a status page.

  Targets only users who own at least one status page (the ones most likely
  to be affected by the "Unknown" display bug).

  ## Usage

      # Dry run — prints recipients, sends nothing
      mix send_apology_email --dry-run

      # Live run — sends to all status page owners
      mix send_apology_email

  """

  use Mix.Task

  @shortdoc "Send status page apology email to status page owners"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry-run" in args

    if dry_run do
      Mix.shell().info("=== DRY RUN — no emails will be sent ===\n")
    end

    alias Uptrack.AppRepo
    import Ecto.Query

    # Find all users who have at least one status page
    users =
      Uptrack.Accounts.User
      |> join(:inner, [u], sp in assoc(u, :status_pages))
      |> distinct([u], u.id)
      |> select([u], u)
      |> AppRepo.all()

    Mix.shell().info("Found #{length(users)} users with status pages\n")

    {sent, failed} =
      Enum.reduce(users, {0, 0}, fn user, {sent, failed} ->
        if dry_run do
          Mix.shell().info("  [DRY RUN] Would send to: #{user.email} (#{user.name})")
          {sent + 1, failed}
        else
          email = Uptrack.Emails.StatusPageApologyEmail.apology_email(user.email, user.name)

          case Uptrack.Mailer.deliver(email) do
            {:ok, _} ->
              Mix.shell().info("  Sent: #{user.email}")
              {sent + 1, failed}

            {:error, reason} ->
              Mix.shell().error("  Failed: #{user.email} — #{inspect(reason)}")
              {sent, failed + 1}
          end
        end
      end)

    Mix.shell().info("\n#{if dry_run, do: "Would send", else: "Sent"}: #{sent}, Failed: #{failed}")
  end
end
