defmodule UptrackWeb.Schemas.Domain do
  @moduledoc """
  OpenAPI schemas for custom domain endpoints.
  """

  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule DnsRecord do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DnsRecord",
      description: "DNS record for domain verification",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Record name (hostname)"},
        type: %Schema{type: :string, enum: ["TXT", "CNAME", "A"], description: "Record type"},
        value: %Schema{type: :string, description: "Record value"}
      },
      example: %{
        name: "_uptrack-verification.status.example.com",
        type: "TXT",
        value: "abc123xyz"
      }
    })
  end

  defmodule DnsRecords do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DnsRecords",
      description: "Required DNS records for domain verification",
      type: :object,
      properties: %{
        txt_record: DnsRecord,
        cname_record: DnsRecord
      }
    })
  end

  defmodule ConfigResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DomainConfigResponse",
      description: "Domain configuration and status",
      type: :object,
      properties: %{
        custom_domain: %Schema{
          type: :string,
          nullable: true,
          description: "Custom domain name"
        },
        domain_verified: %Schema{type: :boolean, description: "Whether domain is verified"},
        domain_verified_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When domain was verified"
        },
        domain_verification_token: %Schema{
          type: :string,
          description: "Token for DNS TXT record verification"
        },
        ssl_status: %Schema{
          type: :string,
          enum: ["pending", "provisioning", "active", "expired", "failed"],
          description: "SSL certificate status"
        },
        ssl_expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "SSL certificate expiration"
        },
        dns_records: %Schema{
          oneOf: [DnsRecords, %Schema{type: :null}],
          description: "Required DNS records (null if no domain set)"
        }
      },
      example: %{
        custom_domain: "status.example.com",
        domain_verified: false,
        domain_verification_token: "abc123xyz",
        ssl_status: "pending",
        dns_records: %{
          txt_record: %{
            name: "_uptrack-verification.status.example.com",
            type: "TXT",
            value: "abc123xyz"
          },
          cname_record: %{
            name: "status.example.com",
            type: "CNAME",
            value: "status.uptrack.dev"
          }
        }
      }
    })
  end

  defmodule UpdateRequest do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DomainUpdateRequest",
      description: "Request to set custom domain",
      type: :object,
      properties: %{
        custom_domain: %Schema{
          type: :string,
          description: "Domain name (e.g., status.example.com)",
          pattern: "^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$"
        }
      },
      required: [:custom_domain],
      example: %{
        custom_domain: "status.example.com"
      }
    })
  end

  defmodule VerifyResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DomainVerifyResponse",
      description: "Domain verification result",
      type: :object,
      properties: %{
        verified: %Schema{type: :boolean, description: "Whether verification succeeded"},
        domain: %Schema{type: :string, description: "The domain that was verified"},
        verified_at: %Schema{type: :string, format: :"date-time", description: "Verification timestamp"},
        message: %Schema{type: :string, description: "Success or error message"},
        error: %Schema{type: :string, nullable: true, description: "Error details if failed"},
        dns_records: %Schema{
          oneOf: [DnsRecords, %Schema{type: :null}],
          description: "Required DNS records (shown on failure)"
        }
      },
      example: %{
        verified: true,
        domain: "status.example.com",
        verified_at: "2024-01-01T00:00:00Z",
        message: "Domain verified successfully"
      }
    })
  end

  defmodule SuccessResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DomainSuccessResponse",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean},
        message: %Schema{type: :string}
      },
      example: %{success: true, message: "Custom domain removed"}
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    OpenApiSpex.schema(%{
      title: "DomainErrorResponse",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message"},
        details: %Schema{type: :object, description: "Validation error details"}
      },
      example: %{error: "Status page not found"}
    })
  end
end
