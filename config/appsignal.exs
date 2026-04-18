import Config

config :appsignal, :config,
  otp_app: :uptrack,
  name: "Uptrack API",
  push_api_key: "fd79d6c0-9a8d-4820-95c8-933f8fc0c9cb",
  env: Mix.env(),
  enable_error_backend: true

