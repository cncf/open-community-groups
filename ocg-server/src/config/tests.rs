use deadpool_postgres::Config as DeadpoolDbConfig;
use ocg_common::config::LogFormat;

use super::*;

#[test]
fn test_badges_config_rejects_invalid_keys() {
    // Setup invalid identifiers, mismatched material, and duplicate identifiers
    let private_jwk = JWK::generate_ed25519().unwrap();
    let mut mismatched = private_jwk.clone();
    let Params::OKP(params) = &mut mismatched.params else {
        unreachable!();
    };
    params.public_key.0[0] ^= 1;
    let public_jwk = private_jwk.to_public();

    let invalid_id = BadgesConfig {
        signing_key: BadgeSigningKeyConfig {
            key_id: "Not Stable".to_string(),
            private_jwk: private_jwk.clone(),
        },
        verification_keys: vec![],
    };
    let mismatched_key = BadgesConfig {
        signing_key: BadgeSigningKeyConfig {
            key_id: "active-2026".to_string(),
            private_jwk: mismatched,
        },
        verification_keys: vec![],
    };
    let duplicate = BadgesConfig {
        signing_key: BadgeSigningKeyConfig {
            key_id: "active-2026".to_string(),
            private_jwk,
        },
        verification_keys: vec![BadgeVerificationKeyConfig {
            key_id: "active-2026".to_string(),
            public_jwk,
        }],
    };
    // Validate each inconsistent key configuration
    let duplicate_result = duplicate.validate();
    let invalid_id_result = invalid_id.validate();
    let mismatched_key_result = mismatched_key.validate();

    // Check every inconsistent configuration is rejected
    assert!(duplicate_result.is_err());
    assert!(invalid_id_result.is_err());
    assert!(mismatched_key_result.is_err());
}

#[test]
fn test_config_debug_redacts_sensitive_values() {
    // Setup config with sentinel secret values
    let cfg = sample_config();
    let outputs = [
        format!("{cfg:?}"),
        format!("{:?}", cfg.email.smtp),
        format!("{:?}", cfg.images),
        format!("{:?}", cfg.meetings),
        format!("{:?}", cfg.payments),
        format!("{:?}", cfg.server.badges),
        format!("{:?}", cfg.server.oauth2),
        format!("{:?}", cfg.server.oidc),
    ];

    // Check root and nested debug output redacts all secret values
    for output in outputs {
        for sensitive_value in sensitive_values() {
            assert!(
                !output.contains(sensitive_value),
                "debug output exposed sensitive value '{sensitive_value}': {output}"
            );
        }
        assert!(output.contains(REDACTED_CONFIG_VALUE));
    }
}

#[test]
fn test_config_rejects_missing_badges_configuration() {
    // Remove the required badge configuration from an otherwise valid config
    let mut cfg = sample_config();
    cfg.server.badges = None;

    // Validate the complete startup configuration
    let result = cfg.validate();

    // Check startup rejects a partially configured public badge service
    assert_eq!(result.unwrap_err().to_string(), "server.badges is required");
}

#[test]
fn test_external_payments_config_accepts_mixed_case_country_codes() {
    // Setup a valid allowlist that still needs case normalization
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec!["kr".to_string(), "NG".to_string()],
        default_payment_window_hours: DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS,
        max_payment_window_hours: DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS,
    };

    // Validate and normalize the allowlist
    let result = cfg.validate();

    // Check mixed-case alpha-2 codes are accepted and uppercased for sync
    assert!(result.is_ok());
    assert_eq!(
        cfg.allowed_countries_normalized(),
        vec!["KR".to_string(), "NG".to_string()]
    );
}

#[test]
fn test_external_payments_config_defaults_window_hours() {
    // Setup serialized config that omits optional window limits
    let cfg: ExternalPaymentsConfig = serde_json::from_value(serde_json::json!({
        "allowed_countries": ["KR"],
    }))
    .unwrap();

    // Check omitted windows use the documented operator defaults
    assert_eq!(
        cfg.default_payment_window_hours,
        DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS
    );
    assert_eq!(
        cfg.max_payment_window_hours,
        DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS
    );
    assert!(cfg.validate().is_ok());
}

#[test]
fn test_external_payments_config_rejects_default_window_above_max() {
    // Setup a default window longer than the configured maximum
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec!["KR".to_string()],
        default_payment_window_hours: 48,
        max_payment_window_hours: 24,
    };

    // Validate the inconsistent window limits
    let result = cfg.validate();

    // Check startup rejects a default that cannot be enforced
    assert_eq!(
        result.unwrap_err().to_string(),
        "external_payments.default_payment_window_hours cannot exceed max_payment_window_hours"
    );
}

#[test]
fn test_external_payments_config_rejects_duplicate_country_codes() {
    // Setup an allowlist with the same country in different case
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec!["KR".to_string(), "kr".to_string()],
        default_payment_window_hours: DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS,
        max_payment_window_hours: DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS,
    };

    // Validate the duplicated country codes
    let result = cfg.validate();

    // Check case-insensitive duplicates are rejected
    assert_eq!(
        result.unwrap_err().to_string(),
        "external_payments.allowed_countries contains duplicate country code 'kr'"
    );
}

#[test]
fn test_external_payments_config_rejects_empty_allowlist() {
    // Setup a present config section with no countries
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec![],
        default_payment_window_hours: DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS,
        max_payment_window_hours: DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS,
    };

    // Validate the empty allowlist
    let result = cfg.validate();

    // Check startup rejects a configured-but-empty allowlist
    assert_eq!(
        result.unwrap_err().to_string(),
        "external_payments.allowed_countries cannot be empty"
    );
}

#[test]
fn test_external_payments_config_rejects_invalid_country_code() {
    // Setup an allowlist entry that is not an ISO 3166-1 alpha-2 code
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec!["KOR".to_string()],
        default_payment_window_hours: DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS,
        max_payment_window_hours: DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS,
    };

    // Validate the invalid country code
    let result = cfg.validate();

    // Check startup rejects codes that cannot match group.country_code
    assert_eq!(
        result.unwrap_err().to_string(),
        "external_payments.allowed_countries contains invalid country code 'KOR'"
    );
}

#[test]
fn test_external_payments_config_rejects_non_positive_window_hours() {
    // Setup a non-positive default window
    let cfg = ExternalPaymentsConfig {
        allowed_countries: vec!["KR".to_string()],
        default_payment_window_hours: 0,
        max_payment_window_hours: DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS,
    };

    // Validate the non-positive window
    let result = cfg.validate();

    // Check startup rejects a window that cannot schedule a hold
    assert_eq!(
        result.unwrap_err().to_string(),
        "external_payments.default_payment_window_hours must be at least 1"
    );
}

#[test]
fn test_http_client_config_defaults_deadlines() {
    // Setup a section that omits every deadline
    let cfg: HttpClientConfig = serde_json::from_value(serde_json::json!({})).unwrap();

    // Check the documented defaults apply
    assert_eq!(cfg.connect_timeout(), Duration::from_secs(10));
    assert_eq!(cfg.request_timeout(), Duration::from_secs(30));
}

#[test]
fn test_http_client_config_rejects_zero_connect_timeout() {
    // Setup a section with a zero connection deadline
    let cfg = HttpClientConfig {
        connect_timeout_secs: 0,
        request_timeout_secs: 30,
    };

    // Check the section name is carried in the rejection
    assert_eq!(
        cfg.validate("payments.http_client").unwrap_err().to_string(),
        "payments.http_client.connect_timeout_secs must be >= 1"
    );
}

#[test]
fn test_http_client_config_rejects_zero_request_timeout() {
    // Setup a section with a zero request deadline
    let cfg = HttpClientConfig {
        connect_timeout_secs: 10,
        request_timeout_secs: 0,
    };

    // Check the section name is carried in the rejection
    assert_eq!(
        cfg.validate("server.http_client").unwrap_err().to_string(),
        "server.http_client.request_timeout_secs must be >= 1"
    );
}

#[test]
fn test_http_server_config_defaults_deadlines_and_grace_period() {
    // Setup a server section that omits the outbound client and shutdown settings
    let cfg: HttpServerConfig = serde_json::from_value(sample_http_server_config_value()).unwrap();

    // Check the documented defaults apply
    assert_eq!(cfg.http_client, HttpClientConfig::default());
    assert_eq!(cfg.shutdown_grace_period(), Duration::from_secs(30));
}

#[test]
fn test_http_server_config_defaults_image_hotlinking_to_false() {
    let cfg: HttpServerConfig = serde_json::from_value(sample_http_server_config_value()).unwrap();

    assert!(!cfg.allow_image_hotlinking);
}

#[test]
fn test_http_server_config_defaults_max_blocking_concurrency_to_parallelism() {
    // Setup a server section that omits the blocking bound
    let cfg: HttpServerConfig = serde_json::from_value(sample_http_server_config_value()).unwrap();

    // Check the bound follows the host parallelism and is never zero
    assert_eq!(
        cfg.max_blocking_concurrency(),
        std::thread::available_parallelism().map_or(1, std::num::NonZero::get)
    );
    assert!(cfg.max_blocking_concurrency() >= 1);
}

#[test]
fn test_http_server_config_ignores_removed_referer_setting() {
    let mut value = sample_http_server_config_value();
    value["disable_referer_checks"] = serde_json::Value::Bool(true);

    let cfg: HttpServerConfig = serde_json::from_value(value).unwrap();

    assert!(!cfg.allow_image_hotlinking);
}

#[test]
fn test_http_server_config_rejects_zero_max_blocking_concurrency() {
    // Setup a server section with a zero blocking bound
    let mut cfg = sample_config().server;
    cfg.max_blocking_concurrency = Some(0);

    // Check the server section rejects the bound
    assert_eq!(
        cfg.validate().unwrap_err().to_string(),
        "server.max_blocking_concurrency must be >= 1"
    );
}

#[test]
fn test_http_server_config_uses_image_hotlinking_setting() {
    let mut value = sample_http_server_config_value();
    value["allow_image_hotlinking"] = serde_json::Value::Bool(true);

    let cfg: HttpServerConfig = serde_json::from_value(value).unwrap();

    assert!(cfg.allow_image_hotlinking);
}

#[test]
fn test_payments_config_accepts_maximum_platform_fee_bps() {
    // Setup a Stripe configuration with the maximum platform fee
    let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
        unreachable!();
    };
    cfg.platform_fee_bps = MAX_PLATFORM_FEE_BPS;

    // Validate the Stripe payments configuration
    let result = cfg.validate();

    // Check the largest fee strictly below the charge is accepted
    assert!(result.is_ok());
}

#[test]
fn test_payments_config_defaults_platform_fee_bps_to_zero() {
    // Setup a Stripe configuration without a platform fee entry
    let cfg: PaymentsConfig = serde_json::from_value(serde_json::json!({
        "provider": "stripe",
        "connected_webhook_secret": "whsec_connect_secret",
        "mode": "test",
        "secret_key": "sk_test_secret",
        "ticket_tax_api_version": "2026-07-29.preview",
        "webhook_secret": "whsec_secret",
    }))
    .unwrap();

    // Check the platform fee defaults to zero (no fee)
    assert_eq!(cfg.platform_fee_bps(), 0);
}

#[test]
fn test_payments_config_rejects_zero_http_client_deadline() {
    // Setup a Stripe configuration with a zero request deadline
    let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
        unreachable!();
    };
    cfg.http_client.request_timeout_secs = 0;

    // Check the Stripe section rejects the deadline
    assert_eq!(
        cfg.validate().unwrap_err().to_string(),
        "payments.http_client.request_timeout_secs must be >= 1"
    );
}

#[test]
fn test_payments_config_rejects_platform_fee_bps_above_maximum() {
    // Setup a Stripe configuration with an out-of-range platform fee
    let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
        unreachable!();
    };
    cfg.platform_fee_bps = MAX_PLATFORM_FEE_BPS + 1;

    // Validate the Stripe payments configuration
    let result = cfg.validate();

    // Check the out-of-range fee is rejected
    assert_eq!(
        result.unwrap_err().to_string(),
        "payments.platform_fee_bps cannot exceed 9999"
    );
}

#[test]
fn test_payments_config_rejects_blank_connected_webhook_secret() {
    // Setup a Stripe configuration with a blank Connect webhook secret
    let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
        unreachable!();
    };
    cfg.connected_webhook_secret = "  ".to_string();

    // Validate the Stripe payments configuration
    let result = cfg.validate();

    // Check startup rejects a secret that cannot verify Connect events
    assert_eq!(
        result.unwrap_err().to_string(),
        "payments.connected_webhook_secret cannot be empty"
    );
}

#[test]
fn test_payments_config_rejects_blank_ticket_tax_api_version() {
    // Setup a Stripe configuration with a blank ticket-tax API version
    let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
        unreachable!();
    };
    cfg.ticket_tax_api_version = "  ".to_string();

    // Validate the Stripe payments configuration
    let result = cfg.validate();

    // Check startup rejects a version that cannot be sent to Stripe
    assert_eq!(
        result.unwrap_err().to_string(),
        "payments.ticket_tax_api_version cannot be empty"
    );
}

#[test]
fn test_payments_config_rejects_missing_connected_webhook_secret() {
    // Setup serialized Stripe configuration without a Connect webhook secret
    let result = serde_json::from_value::<PaymentsConfig>(serde_json::json!({
        "provider": "stripe",
        "mode": "test",
        "secret_key": "sk_test_secret",
        "ticket_tax_api_version": "2026-07-29.preview",
        "webhook_secret": "whsec_secret",
    }));

    // Check deserialization rejects an unverifiable Connect configuration
    assert!(result.is_err());
}

#[test]
fn test_payments_config_rejects_missing_ticket_tax_api_version() {
    // Setup serialized Stripe configuration without the ticket-tax API version
    let result = serde_json::from_value::<PaymentsConfig>(serde_json::json!({
        "provider": "stripe",
        "connected_webhook_secret": "whsec_connect_secret",
        "mode": "test",
        "secret_key": "sk_test_secret",
        "webhook_secret": "whsec_secret",
    }));

    // Check deserialization rejects an incomplete tax and credit-note configuration
    assert!(result.is_err());
}

#[test]
fn test_smtp_config_defaults_deadlines() {
    // Setup an SMTP section that omits both deadlines
    let cfg: SmtpConfig = serde_json::from_value(serde_json::json!({
        "host": "smtp.example.test",
        "password": "smtp-sensitive-value",
        "port": 587,
        "username": "smtp-user",
    }))
    .unwrap();

    // Check the documented defaults apply
    assert_eq!(cfg.connect_timeout(), Duration::from_secs(10));
    assert_eq!(cfg.send_timeout(), Duration::from_secs(30));
}

#[test]
fn test_smtp_config_rejects_zero_send_timeout() {
    // Setup an SMTP section with a zero delivery deadline
    let mut cfg = sample_config().email.smtp;
    cfg.send_timeout_secs = 0;

    // Check the email section rejects the deadline
    assert_eq!(
        cfg.validate().unwrap_err().to_string(),
        "email.smtp.send_timeout_secs must be >= 1"
    );
}

// Helpers.

fn sample_config() -> Config {
    let badge_signing_key = JWK::generate_ed25519().unwrap();
    let mut oauth2 = HashMap::new();
    oauth2.insert(
        OAuth2Provider::GitHub,
        OAuth2ProviderConfig {
            auth_url: "https://github.example.test/auth".to_string(),
            client_id: "github-client-id".to_string(),
            client_secret: "oauth2-sensitive-value".to_string(),
            redirect_uri: "https://app.example.test/auth/github/callback".to_string(),
            scopes: vec!["user:email".to_string()],
            token_url: "https://github.example.test/token".to_string(),
        },
    );

    let mut oidc = HashMap::new();
    oidc.insert(
        OidcProvider::LinuxFoundation,
        OidcProviderConfig {
            client_id: "lf-client-id".to_string(),
            client_secret: "oidc-sensitive-value".to_string(),
            issuer_url: "https://oidc.example.test".to_string(),
            redirect_uri: "https://app.example.test/auth/lf/callback".to_string(),
            scopes: vec!["openid".to_string(), "email".to_string()],
        },
    );

    Config {
        db: sample_db_config(),
        email: EmailConfig {
            from_address: "noreply@example.test".to_string(),
            from_name: "OCG".to_string(),
            smtp: SmtpConfig {
                host: "smtp.example.test".to_string(),
                password: "smtp-sensitive-value".to_string(),
                port: 587,
                username: "smtp-user".to_string(),

                connect_timeout_secs: DEFAULT_CONNECT_TIMEOUT_SECS,
                send_timeout_secs: DEFAULT_REQUEST_TIMEOUT_SECS,
            },
            rcpts_whitelist: None,
        },
        images: ImageStorageConfig::S3(ImageStorageConfigS3 {
            access_key_id: "s3-access-key-id".to_string(),
            bucket: "images".to_string(),
            region: "eu-west-1".to_string(),
            secret_access_key: "s3-sensitive-value".to_string(),
            endpoint: Some("https://s3.example.test".to_string()),
            force_path_style: Some(true),
        }),
        log: LogConfig {
            format: LogFormat::Json,
        },
        server: HttpServerConfig {
            addr: "127.0.0.1:9000".to_string(),
            base_url: "https://app.example.test".to_string(),
            login: LoginOptions {
                email: true,
                github: true,
                linuxfoundation: true,
            },
            oauth2,
            oidc,

            allow_image_hotlinking: false,
            badges: Some(BadgesConfig {
                signing_key: BadgeSigningKeyConfig {
                    key_id: "config-test".to_string(),
                    private_jwk: badge_signing_key,
                },
                verification_keys: vec![],
            }),
            cookie: None,
            http_client: HttpClientConfig::default(),
            max_blocking_concurrency: None,
            redirect_hosts: None,
            shutdown_grace_period_secs: DEFAULT_SHUTDOWN_GRACE_PERIOD_SECS,
        },
        external_payments: None,
        meetings: Some(MeetingsConfig {
            zoom: Some(MeetingsZoomConfig {
                account_id: "zoom-account-id".to_string(),
                client_id: "zoom-client-id".to_string(),
                client_secret: "zoom-client-sensitive-value".to_string(),
                enabled: true,
                host_pool_users: vec!["host@example.test".to_string()],
                max_participants: 100,
                max_simultaneous_meetings_per_host: 2,
                webhook_secret_token: "zoom-webhook-sensitive-value".to_string(),

                http_client: HttpClientConfig::default(),
            }),
        }),
        payments: Some(PaymentsConfig::Stripe(PaymentsStripeConfig {
            connected_webhook_secret: "stripe-connect-webhook-sensitive-value".to_string(),
            mode: PaymentMode::Test,
            secret_key: "stripe-key-sensitive-value".to_string(),
            ticket_tax_api_version: "2026-07-29.preview".to_string(),
            webhook_secret: "stripe-webhook-sensitive-value".to_string(),

            http_client: HttpClientConfig::default(),
            platform_fee_bps: 250,
        })),
    }
}

fn sample_db_config() -> DbConfig {
    let url = "postgres://user:db-url-sensitive-value@db.example.test/ocg";
    let mut connection = DeadpoolDbConfig::new();
    connection.password = Some("db-password-sensitive-value".to_string());
    connection.url = Some(url.to_string());

    DbConfig {
        connection,

        tls: None,
    }
}

fn sample_http_server_config_value() -> serde_json::Value {
    serde_json::json!({
        "addr": "127.0.0.1:9000",
        "base_url": "https://example.test",
        "login": {
            "email": false,
            "github": false,
            "linuxfoundation": false,
        },
        "oauth2": {},
        "oidc": {},
    })
}

fn sensitive_values() -> [&'static str; 11] {
    [
        "db-password-sensitive-value",
        "db-url-sensitive-value",
        "oauth2-sensitive-value",
        "oidc-sensitive-value",
        "s3-sensitive-value",
        "stripe-connect-webhook-sensitive-value",
        "smtp-sensitive-value",
        "stripe-key-sensitive-value",
        "stripe-webhook-sensitive-value",
        "zoom-client-sensitive-value",
        "zoom-webhook-sensitive-value",
    ]
}
