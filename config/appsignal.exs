import Config

config :appsignal, :config,
  otp_app: :uptrack,
  name: "Uptrack API",
  push_api_key: "REMOVED_APPSIGNAL_KEY",
  env: Mix.env(),
  enable_error_backend: true

