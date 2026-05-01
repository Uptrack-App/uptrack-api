import Config

config :appsignal, :config,
  otp_app: :uptrack,
  name: "Uptrack API",
  push_api_key: System.get_env("APPSIGNAL_PUSH_API_KEY"),
  env: Mix.env(),
  # Sentry owns error reporting; AppSignal stays APM-only to avoid duplicate alerts.
  enable_error_backend: false

