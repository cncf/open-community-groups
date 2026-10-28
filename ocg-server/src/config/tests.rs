use deadpool_postgres::Config as DeadpoolDbConfig;
use ocg_common::config::LogFormat;

use super::*;

#[test]
fn test_badges_config_rejects_invalid_keys() {
    // Setup a signing key, a public key of another key pair, and mismatched material
    let private_jwk = JWK::generate_ed25519().unwrap();
    let other_private_jwk = JWK::generate_ed25519().unwrap();
    let mut mismatched_jwk = private_jwk.clone();
    let (Params::OKP(mismatched), Params::OKP(other)) =
        (&mut mismatched_jwk.params, &other_private_jwk.params)
    else {
        unreachable!();
    };
    mismatched.public_key = other.public_key.clone();
    let signing_key = |key_id: &str, private_jwk: &JWK| BadgeSigningKeyConfig {
        key_id: key_id.to_string(),
        private_jwk: private_jwk.clone(),
    };
    let verification_key = |key_id: &str, public_jwk: &JWK| BadgeVerificationKeyConfig {
        key_id: key_id.to_string(),
        public_jwk: public_jwk.clone(),
    };

    // (case, signing key, verification keys, expected error)
    let cases = [
        (
            "unstable key identifier",
            signing_key("Not Stable", &private_jwk),
            vec![],
            "server.badges key identifiers must be 1-64 lowercase URL-safe characters and start and end with a letter or digit",
        ),
        (
            "signing key without private material",
            signing_key("active-2026", &private_jwk.to_public()),
            vec![],
            "server.badges signing key must contain an Ed25519 private key",
        ),
        (
            "mismatched key material",
            signing_key("active-2026", &mismatched_jwk),
            vec![],
            "server.badges signing key public and private material must match",
        ),
        (
            "verification key with private material",
            signing_key("active-2026", &private_jwk),
            vec![verification_key("retired-2025", &other_private_jwk)],
            "server.badges verification keys must contain public material only",
        ),
        (
            "duplicate key identifiers",
            signing_key("active-2026", &private_jwk),
            vec![verification_key("active-2026", &private_jwk.to_public())],
            "server.badges contains duplicate key identifiers",
        ),
    ];

    for (case, signing_key, verification_keys, expected) in cases {
        let cfg = BadgesConfig {
            signing_key,
            verification_keys,
        };

        assert_eq!(cfg.validate().unwrap_err().to_string(), expected, "{case}");
    }
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
fn test_external_payments_config_rejects_invalid_settings() {
    let default_hours = DEFAULT_EXTERNAL_PAYMENT_WINDOW_HOURS;
    let max_hours = DEFAULT_MAX_EXTERNAL_PAYMENT_WINDOW_HOURS;
    // (case, allowed countries, default window hours, max window hours, expected error)
    let cases = [
        (
            "empty allowlist",
            vec![],
            default_hours,
            max_hours,
            "external_payments.allowed_countries cannot be empty",
        ),
        (
            "invalid country code",
            vec!["KOR"],
            default_hours,
            max_hours,
            "external_payments.allowed_countries contains invalid country code 'KOR'",
        ),
        (
            "duplicate country code in different case",
            vec!["KR", "kr"],
            default_hours,
            max_hours,
            "external_payments.allowed_countries contains duplicate country code 'kr'",
        ),
        (
            "non-positive default window",
            vec!["KR"],
            0,
            max_hours,
            "external_payments.default_payment_window_hours must be at least 1",
        ),
        (
            "non-positive max window",
            vec!["KR"],
            1,
            0,
            "external_payments.max_payment_window_hours must be at least 1",
        ),
        (
            "default window above max",
            vec!["KR"],
            48,
            24,
            "external_payments.default_payment_window_hours cannot exceed max_payment_window_hours",
        ),
    ];

    for (
        case,
        allowed_countries,
        default_payment_window_hours,
        max_payment_window_hours,
        expected,
    ) in cases
    {
        let cfg = ExternalPaymentsConfig {
            allowed_countries: allowed_countries.into_iter().map(str::to_string).collect(),
            default_payment_window_hours,
            max_payment_window_hours,
        };

        assert_eq!(cfg.validate().unwrap_err().to_string(), expected, "{case}");
    }
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
fn test_http_client_config_rejects_zero_timeouts() {
    // (case, connect timeout, request timeout, section, expected error)
    let cases = [
        (
            "zero connect timeout",
            0,
            30,
            "payments.http_client",
            "payments.http_client.connect_timeout_secs must be >= 1",
        ),
        (
            "zero request timeout",
            10,
            0,
            "server.http_client",
            "server.http_client.request_timeout_secs must be >= 1",
        ),
    ];

    for (case, connect_timeout_secs, request_timeout_secs, section, expected) in cases {
        let cfg = HttpClientConfig {
            connect_timeout_secs,
            request_timeout_secs,
        };

        // Check the section name is carried in the rejection
        assert_eq!(
            cfg.validate(section).unwrap_err().to_string(),
            expected,
            "{case}"
        );
    }
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
fn test_http_server_config_deserializes_image_hotlinking() {
    // (case, extra setting, expected allow_image_hotlinking)
    let cases = [
        ("omitted", None, false),
        ("enabled", Some("allow_image_hotlinking"), true),
        (
            "removed referer setting",
            Some("disable_referer_checks"),
            false,
        ),
    ];

    for (case, setting, expected) in cases {
        let mut value = sample_http_server_config_value();
        if let Some(setting) = setting {
            value[setting] = serde_json::Value::Bool(true);
        }

        let cfg: HttpServerConfig = serde_json::from_value(value).expect(case);

        assert_eq!(cfg.allow_image_hotlinking, expected, "{case}");
    }
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
fn test_meetings_config_meeting_limits_by_provider_includes_zoom_limits() {
    let meetings_cfg = sample_config().meetings.unwrap();

    assert_eq!(
        meetings_cfg.meeting_limits_by_provider(),
        HashMap::from([(
            MeetingProvider::Zoom,
            MeetingProviderLimits {
                max_duration_minutes: 720,
                max_participants: 100,
                min_duration_minutes: 5,
            },
        )])
    );
}

#[test]
fn test_meetings_config_meeting_limits_by_provider_is_empty_without_providers() {
    assert!(MeetingsConfig::default().meeting_limits_by_provider().is_empty());
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
    let cfg: PaymentsConfig = serde_json::from_value(sample_stripe_config_value()).unwrap();

    // Check the platform fee defaults to zero (no fee)
    assert_eq!(cfg.platform_fee_bps(), 0);
}

#[test]
fn test_payments_config_rejects_invalid_stripe_settings() {
    type Change = fn(&mut PaymentsStripeConfig);

    // (case, setting change, expected error)
    let cases: [(&str, Change, &str); 6] = [
        (
            "zero http client deadline",
            |cfg| cfg.http_client.request_timeout_secs = 0,
            "payments.http_client.request_timeout_secs must be >= 1",
        ),
        (
            "platform fee above maximum",
            |cfg| cfg.platform_fee_bps = MAX_PLATFORM_FEE_BPS + 1,
            "payments.platform_fee_bps cannot exceed 9999",
        ),
        (
            "blank connected webhook secret",
            |cfg| cfg.connected_webhook_secret = "  ".to_string(),
            "payments.connected_webhook_secret cannot be empty",
        ),
        (
            "blank secret key",
            |cfg| cfg.secret_key = "  ".to_string(),
            "payments.secret_key cannot be empty",
        ),
        (
            "blank ticket tax API version",
            |cfg| cfg.ticket_tax_api_version = "  ".to_string(),
            "payments.ticket_tax_api_version cannot be empty",
        ),
        (
            "blank webhook secret",
            |cfg| cfg.webhook_secret = "  ".to_string(),
            "payments.webhook_secret cannot be empty",
        ),
    ];

    for (case, change, expected) in cases {
        let Some(PaymentsConfig::Stripe(mut cfg)) = sample_config().payments else {
            unreachable!();
        };
        change(&mut cfg);

        assert_eq!(cfg.validate().unwrap_err().to_string(), expected, "{case}");
    }
}

#[test]
fn test_payments_config_requires_stripe_fields() {
    for field in ["connected_webhook_secret", "ticket_tax_api_version"] {
        // Setup serialized Stripe configuration without the field
        let mut value = sample_stripe_config_value();
        value.as_object_mut().unwrap().remove(field);

        // Check deserialization names the missing field
        let error = serde_json::from_value::<PaymentsConfig>(value).unwrap_err();
        assert!(
            error.to_string().contains(&format!("missing field `{field}`")),
            "{field}: {error}"
        );
    }
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

// Shared configuration samples.

/// Sample badge signing configuration with a freshly generated key.
pub(crate) fn sample_badges_cfg() -> BadgesConfig {
    BadgesConfig {
        signing_key: BadgeSigningKeyConfig {
            key_id: "test-key".to_string(),
            private_jwk: JWK::generate_ed25519().expect("test signing key generation to succeed"),
        },
        verification_keys: vec![],
    }
}

/// Sample Stripe payments configuration.
pub(crate) fn sample_payments_cfg() -> PaymentsConfig {
    PaymentsConfig::Stripe(PaymentsStripeConfig {
        connected_webhook_secret: "whsec_connect_test".to_string(),
        mode: PaymentMode::Test,
        secret_key: "sk_test".to_string(),
        ticket_tax_api_version: "2026-07-29.preview".to_string(),
        webhook_secret: "whsec_test".to_string(),

        http_client: HttpClientConfig::default(),
        platform_fee_bps: 0,
    })
}

/// Sample HTTP server configuration with the given public base URL.
pub(crate) fn sample_server_cfg(base_url: &str) -> HttpServerConfig {
    HttpServerConfig {
        base_url: base_url.to_string(),
        ..Default::default()
    }
}

/// Sample enabled Zoom configuration with the given webhook secret token.
pub(crate) fn sample_zoom_cfg(webhook_secret_token: &str) -> MeetingsZoomConfig {
    MeetingsZoomConfig {
        account_id: "account-id".to_string(),
        client_id: "client-id".to_string(),
        client_secret: "client-secret".to_string(),
        enabled: true,
        host_pool_users: vec!["host@example.com".to_string()],
        max_participants: 100,
        max_simultaneous_meetings_per_host: 1,
        webhook_secret_token: webhook_secret_token.to_string(),

        http_client: HttpClientConfig::default(),
    }
}

/// Sample meetings configuration with Zoom enabled and the given webhook
/// secret token.
pub(crate) fn sample_zoom_meetings_cfg(webhook_secret_token: &str) -> MeetingsConfig {
    MeetingsConfig {
        zoom: Some(sample_zoom_cfg(webhook_secret_token)),
    }
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

fn sample_stripe_config_value() -> serde_json::Value {
    serde_json::json!({
        "provider": "stripe",
        "connected_webhook_secret": "whsec_connect_secret",
        "mode": "test",
        "secret_key": "sk_test_secret",
        "ticket_tax_api_version": "2026-07-29.preview",
        "webhook_secret": "whsec_secret",
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
