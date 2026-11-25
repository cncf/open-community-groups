use deadpool_postgres::Config as DeadpoolDbConfig;
use ocg_common::config::LogFormat;
use serde_json::json;

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
fn test_client_ip_header_config_trusted_networks_accepts_valid_entries() {
    // (case, entry, expected network)
    let cases = [
        ("bare IPv4 address", "192.0.2.10", "192.0.2.10/32"),
        ("bare IPv6 address", "2001:db8::10", "2001:db8::10/128"),
        ("IPv4 network", "10.0.0.0/8", "10.0.0.0/8"),
        ("IPv6 network", "2001:db8::/32", "2001:db8::/32"),
        (
            "IPv4 single-address network",
            "198.51.100.7/32",
            "198.51.100.7/32",
        ),
    ];

    for (case, entry, expected) in cases {
        let cfg = ClientIpHeaderConfig {
            header: DEFAULT_CLIENT_IP_HEADER.to_string(),
            trusted_proxies: vec![entry.to_string()],
        };

        // Check the entry becomes the expected network
        assert_eq!(
            cfg.trusted_networks().expect(case),
            vec![expected.parse::<IpNet>().unwrap()],
            "{case}"
        );
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
fn test_http_server_config_deserializes_without_rate_limit() {
    // Setup a server section that omits the rate limiting section
    let cfg: HttpServerConfig = serde_json::from_value(sample_http_server_config_value()).unwrap();

    // Check rate limiting stays disabled
    assert_eq!(cfg.rate_limit, None);
}

#[test]
fn test_http_server_config_rejects_invalid_rate_limit() {
    // Setup a server section with an invalid rate limit budget
    let mut cfg = sample_config().server;
    let mut rate_limit_cfg = sample_rate_limit_config();
    rate_limit_cfg.limits.views.burst = 0;
    cfg.rate_limit = Some(rate_limit_cfg);

    // Check the server section validates the rate limiting section
    assert_eq!(
        cfg.validate().unwrap_err().to_string(),
        "server.rate_limit.limits.views.burst must be between 1 and 100000"
    );
}

#[test]
fn test_http_server_config_rejects_invalid_security() {
    // Setup a server section with a directive-injecting CSP report URI
    let mut cfg = sample_config().server;
    cfg.security.csp_report_uri = Some("https://reports.example.test/csp; img-src *".to_string());

    // Check the server section validates the security section
    assert_eq!(
        cfg.validate().unwrap_err().to_string(),
        "server.security.csp_report_uri must be a valid URI without whitespace or separators"
    );
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
fn test_image_storage_config_s3_defaults_deadlines() {
    // Setup an S3 image storage section that omits both deadlines
    let cfg: ImageStorageConfig = serde_json::from_value(json!({
        "provider": "s3",
        "access_key_id": "s3-access-key-id",
        "bucket": "images",
        "region": "eu-west-1",
        "secret_access_key": "s3-sensitive-value",
    }))
    .unwrap();

    // Check the documented defaults apply and pass validation
    let ImageStorageConfig::S3(s3_cfg) = cfg else {
        panic!("expected S3 image storage configuration");
    };
    assert_eq!(s3_cfg.connect_timeout(), Duration::from_secs(10));
    assert_eq!(s3_cfg.request_timeout(), Duration::from_secs(30));
    assert!(s3_cfg.validate().is_ok());
}

#[test]
fn test_image_storage_config_s3_rejects_zero_timeouts() {
    type Change = fn(&mut ImageStorageConfigS3);

    // (case, setting change, expected error)
    let cases: [(&str, Change, &str); 2] = [
        (
            "zero connect timeout",
            |cfg| cfg.connect_timeout_secs = 0,
            "images.connect_timeout_secs must be >= 1",
        ),
        (
            "zero request timeout",
            |cfg| cfg.request_timeout_secs = 0,
            "images.request_timeout_secs must be >= 1",
        ),
    ];

    for (case, change, expected) in cases {
        let mut cfg = sample_config();
        let ImageStorageConfig::S3(s3_cfg) = &mut cfg.images else {
            unreachable!();
        };
        change(s3_cfg);

        // Check root startup validation rejects the zero deadline
        assert_eq!(cfg.validate().unwrap_err().to_string(), expected, "{case}");
    }
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
fn test_rate_limit_config_accepts_valid_settings() {
    // (case, rate limit section)
    let cases = [
        ("peer source", json!({ "client_ip": { "source": "peer" } })),
        (
            "header source without trusted proxies",
            json!({ "client_ip": { "source": "header", "trusted_proxies": [] } }),
        ),
        (
            "single-value header",
            json!({ "client_ip": { "source": "header", "header": "CF-Connecting-IP" } }),
        ),
        (
            "bare IP trusted proxies",
            json!({
                "client_ip": {
                    "source": "header",
                    "trusted_proxies": ["192.0.2.10", "2001:db8::10"],
                },
            }),
        ),
        (
            "maximum trusted proxies",
            json!({
                "client_ip": { "source": "header", "trusted_proxies": trusted_proxies(1_024) },
            }),
        ),
        (
            "minimum budget",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "views": { "burst": 1, "period_secs": 1 } },
            }),
        ),
        (
            "maximum budget",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "log_in": { "burst": 100_000, "period_secs": 86_400 } },
            }),
        ),
        (
            "enforce mode",
            json!({ "client_ip": { "source": "peer" }, "mode": "enforce" }),
        ),
    ];

    for (case, value) in cases {
        let cfg: RateLimitConfig = serde_json::from_value(value).expect(case);

        // Check the section passes validation
        assert!(cfg.validate().is_ok(), "{case}");
    }
}

#[test]
fn test_rate_limit_config_defaults_optional_settings() {
    // Setup a header source section that omits every optional setting
    let cfg: RateLimitConfig =
        serde_json::from_value(json!({ "client_ip": { "source": "header" } })).unwrap();

    // Check the header source defaults
    let ClientIpConfig::Header(header_cfg) = &cfg.client_ip else {
        panic!("expected the header source");
    };
    assert_eq!(header_cfg.header, "x-forwarded-for");
    assert_eq!(header_cfg.header_name().unwrap(), "x-forwarded-for");
    assert_eq!(header_cfg.trusted_proxies, Vec::<String>::new());
    assert_eq!(header_cfg.trusted_networks().unwrap(), Vec::<IpNet>::new());

    // Check the mode and budget defaults
    assert_eq!(cfg.mode, RateLimitMode::Observe);
    assert_eq!(cfg.limits, RateLimitBudgets::default());
    assert_eq!(
        cfg.limits,
        RateLimitBudgets {
            badge_verify: budget(30, 300),
            explore_search: budget(300, 150),
            external_auth: budget(300, 150),
            log_in: budget(300, 300),
            log_in_failures: budget(10, 900),
            sign_up: budget(100, 1200),
            verify_email: budget(100, 1200),
            views: budget(600, 600),
        }
    );
    assert!(cfg.validate().is_ok());
}

#[test]
fn test_rate_limit_config_override_merging() {
    // Setup a file that defines one budget
    let file = r"
server:
  rate_limit:
    client_ip:
      source: peer
    limits:
      views:
        burst: 50
        period_secs: 60
";

    // (case, override key, override value as an environment string, expected limits, expected mode)
    let cases = [
        (
            "mode override",
            "server.rate_limit.mode",
            "enforce",
            RateLimitBudgets {
                views: budget(50, 60),
                ..RateLimitBudgets::default()
            },
            RateLimitMode::Enforce,
        ),
        (
            "one field of a budget the file defines",
            "server.rate_limit.limits.views.burst",
            "75",
            RateLimitBudgets {
                views: budget(75, 60),
                ..RateLimitBudgets::default()
            },
            RateLimitMode::Observe,
        ),
    ];

    for (case, key, value, expected_limits, expected_mode) in cases {
        // Merge the override over the file and extract the section
        let cfg: RateLimitConfig = Figment::from(Yaml::string(file))
            .merge(Serialized::default(key, env_value(value)))
            .extract_inner("server.rate_limit")
            .expect(case);

        // Check only the overridden field changed
        assert_eq!(
            cfg.client_ip,
            ClientIpConfig::Peer(ClientIpPeerConfig {}),
            "{case}"
        );
        assert_eq!(cfg.limits, expected_limits, "{case}");
        assert_eq!(cfg.mode, expected_mode, "{case}");
    }
}

#[test]
fn test_rate_limit_config_override_merging_rejects_incomplete_sections() {
    // (case, file contents, override key, override value as an environment string, expected error)
    let cases = [
        (
            "one field of a budget the file does not define",
            "server:\n  rate_limit:\n    client_ip:\n      source: peer\n",
            "server.rate_limit.limits.log_in.burst",
            "5",
            "missing field `period_secs`",
        ),
        (
            "mode without a file section",
            "server:\n  addr: 127.0.0.1:9000\n",
            "server.rate_limit.mode",
            "enforce",
            "missing field `client_ip`",
        ),
    ];

    for (case, file, key, value, expected) in cases {
        // Merge the override over the file and extract the section
        let result = Figment::from(Yaml::string(file))
            .merge(Serialized::default(key, env_value(value)))
            .extract_inner::<RateLimitConfig>("server.rate_limit");

        // Check the built-in defaults do not complete the section
        let error = result.unwrap_err().to_string();
        assert!(error.contains(expected), "{case}: {error}");
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn test_rate_limit_config_rejects_invalid_settings() {
    // (case, rate limit section, expected error)
    let cases = [
        (
            "zero burst",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "views": { "burst": 0, "period_secs": 60 } },
            }),
            "server.rate_limit.limits.views.burst must be between 1 and 100000",
        ),
        (
            "oversized burst",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "log_in": { "burst": 100_001, "period_secs": 60 } },
            }),
            "server.rate_limit.limits.log_in.burst must be between 1 and 100000",
        ),
        (
            "zero period",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "sign_up": { "burst": 10, "period_secs": 0 } },
            }),
            "server.rate_limit.limits.sign_up.period_secs must be between 1 and 86400",
        ),
        (
            "oversized period",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "log_in_failures": { "burst": 10, "period_secs": 86_401 } },
            }),
            "server.rate_limit.limits.log_in_failures.period_secs must be between 1 and 86400",
        ),
        (
            "partial budget",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "badge_verify": { "burst": 10 } },
            }),
            "missing field `period_secs`",
        ),
        (
            "bad CIDR",
            header_source_with_trusted_proxies(&["10.0.0.0/33"]),
            "server.rate_limit.client_ip.trusted_proxies entry '10.0.0.0/33' is not a valid CIDR or IP address",
        ),
        (
            "unparseable entry",
            header_source_with_trusted_proxies(&["proxy.example.test"]),
            "server.rate_limit.client_ip.trusted_proxies entry 'proxy.example.test' is not a valid CIDR or IP address",
        ),
        (
            "IPv4 host bits set",
            header_source_with_trusted_proxies(&["10.1.2.3/8"]),
            "server.rate_limit.client_ip.trusted_proxies entry '10.1.2.3/8' has host bits set; use '10.0.0.0/8'",
        ),
        (
            "IPv6 host bits set",
            header_source_with_trusted_proxies(&["2001:db8::1/32"]),
            "server.rate_limit.client_ip.trusted_proxies entry '2001:db8::1/32' has host bits set; use '2001:db8::/32'",
        ),
        (
            "IPv4 catch-all",
            header_source_with_trusted_proxies(&["0.0.0.0/0"]),
            "server.rate_limit.client_ip.trusted_proxies entry '0.0.0.0/0' would trust every address",
        ),
        (
            "IPv6 catch-all",
            header_source_with_trusted_proxies(&["::/0"]),
            "server.rate_limit.client_ip.trusted_proxies entry '::/0' would trust every address",
        ),
        (
            "IPv4-mapped catch-all",
            header_source_with_trusted_proxies(&["::ffff:0:0/96"]),
            "server.rate_limit.client_ip.trusted_proxies entry '::ffff:0:0/96' would trust every address",
        ),
        (
            "IPv4-mapped network",
            header_source_with_trusted_proxies(&["::ffff:10.0.0.0/104"]),
            "server.rate_limit.client_ip.trusted_proxies entry '::ffff:10.0.0.0/104' is an IPv4-mapped IPv6 network; use the IPv4 form '10.0.0.0/8'",
        ),
        (
            "IPv4-mapped bare address",
            header_source_with_trusted_proxies(&["::ffff:192.0.2.10"]),
            "server.rate_limit.client_ip.trusted_proxies entry '::ffff:192.0.2.10' is an IPv4-mapped IPv6 network; use the IPv4 form '192.0.2.10/32'",
        ),
        (
            "more than 1024 trusted proxies",
            json!({
                "client_ip": { "source": "header", "trusted_proxies": trusted_proxies(1_025) },
            }),
            "server.rate_limit.client_ip.trusted_proxies cannot have more than 1024 entries",
        ),
        (
            "empty header name",
            json!({ "client_ip": { "source": "header", "header": "" } }),
            "server.rate_limit.client_ip.header cannot be empty",
        ),
        (
            "invalid header name",
            json!({ "client_ip": { "source": "header", "header": "x forwarded for" } }),
            "server.rate_limit.client_ip.header 'x forwarded for' is not a valid header name",
        ),
        (
            "forwarded header name",
            json!({ "client_ip": { "source": "header", "header": "Forwarded" } }),
            "server.rate_limit.client_ip.header cannot be 'forwarded': RFC 7239 syntax is not supported",
        ),
    ];

    for (case, value, expected) in cases {
        // Deserialize and validate the section
        let result = serde_json::from_value::<RateLimitConfig>(value)
            .map_err(anyhow::Error::from)
            .and_then(|cfg| cfg.validate());

        // Check the rejection names the offending key
        assert_eq!(result.unwrap_err().to_string(), expected, "{case}");
    }
}

#[test]
fn test_rate_limit_config_rejects_malformed_sections() {
    // (case, rate limit section, expected error)
    let cases = [
        (
            "unknown key in section",
            json!({ "client_ip": { "source": "peer" }, "extra": true }),
            "unknown field `extra`",
        ),
        (
            "unknown key in header source",
            json!({ "client_ip": { "source": "header", "extra": true } }),
            "unknown field `extra`",
        ),
        (
            "unknown limit",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "log_out": { "burst": 1, "period_secs": 1 } },
            }),
            "unknown field `log_out`",
        ),
        (
            "unknown key in budget",
            json!({
                "client_ip": { "source": "peer" },
                "limits": { "views": { "burst": 1, "period_secs": 1, "extra": 1 } },
            }),
            "unknown field `extra`",
        ),
        (
            "header under peer source",
            json!({ "client_ip": { "source": "peer", "header": "x-real-ip" } }),
            "unknown field `header`",
        ),
        (
            "trusted proxies under peer source",
            json!({ "client_ip": { "source": "peer", "trusted_proxies": [] } }),
            "unknown field `trusted_proxies`",
        ),
        (
            "missing client ip",
            json!({ "mode": "observe" }),
            "missing field `client_ip`",
        ),
        (
            "missing source",
            json!({ "client_ip": { "header": "x-forwarded-for" } }),
            "missing field `source`",
        ),
        (
            "unknown source",
            json!({ "client_ip": { "source": "proxy_protocol" } }),
            "unknown variant `proxy_protocol`",
        ),
        (
            "unknown mode",
            json!({ "client_ip": { "source": "peer" }, "mode": "block" }),
            "unknown variant `block`",
        ),
    ];

    for (case, value, expected) in cases {
        let error = serde_json::from_value::<RateLimitConfig>(value)
            .unwrap_err()
            .to_string();

        // Check deserialization rejects the section
        assert!(error.contains(expected), "{case}: {error}");
    }
}

#[test]
fn test_security_config_defaults_and_accepts_valid_report_uris() {
    // Deserialize an empty security section and verify defaults
    let default_cfg: SecurityConfig = serde_json::from_value(json!({})).unwrap();
    assert!(!default_cfg.csp_report_only);
    assert_eq!(default_cfg.csp_report_uri, None);
    assert!(default_cfg.validate().is_ok());

    // Check root-relative paths and http/https report URIs pass validation
    for uri in [
        "/csp-report",
        "/api/csp/report?env=staging",
        "http://127.0.0.1:9001/csp-report",
        "https://reports.example.test/csp",
    ] {
        let cfg = SecurityConfig {
            csp_report_only: true,
            csp_report_uri: Some(uri.to_string()),
        };
        assert!(cfg.validate().is_ok(), "{uri}");
    }
}

#[test]
fn test_security_config_rejects_invalid_settings() {
    // (case, serialized security section, expected error substring)
    let cases = [
        (
            "empty report uri",
            json!({ "csp_report_uri": "" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "whitespace in report uri",
            json!({ "csp_report_uri": "https://reports.example.test/csp report" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "semicolon directive injection",
            json!({ "csp_report_uri": "https://reports.example.test/csp;script-src *" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "comma policy separator",
            json!({ "csp_report_uri": "https://reports.example.test/csp,default-src *" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "backslash authority prefix",
            json!({ "csp_report_uri": "/\\reports.example.test/csp" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "non-ascii path",
            json!({ "csp_report_uri": "/café" }),
            "server.security.csp_report_uri must be a valid URI without whitespace or separators",
        ),
        (
            "protocol-relative report uri",
            json!({ "csp_report_uri": "//reports.example.test/csp" }),
            "server.security.csp_report_uri must be a relative path or http/https URL",
        ),
        (
            "scheme without authority slashes",
            json!({ "csp_report_uri": "https:reports.example.test/csp" }),
            "server.security.csp_report_uri must be a relative path or http/https URL",
        ),
        (
            "non-http scheme",
            json!({ "csp_report_uri": "javascript:alert(1)" }),
            "server.security.csp_report_uri must be a relative path or http/https URL",
        ),
        (
            "bare non-path string",
            json!({ "csp_report_uri": "reports.example.test/csp" }),
            "server.security.csp_report_uri must be a relative path or http/https URL",
        ),
        (
            "unknown field",
            json!({ "csp_report_url": "https://reports.example.test/csp" }),
            "unknown field `csp_report_url`",
        ),
    ];

    for (case, value, expected) in cases {
        // Deserialize and validate the security section
        let result = serde_json::from_value::<SecurityConfig>(value)
            .map_err(anyhow::Error::from)
            .and_then(|cfg| cfg.validate());

        // Check validation rejects the invalid setting with the expected message
        let error = result.unwrap_err().to_string();
        assert!(error.contains(expected), "{case}: {error}");
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

fn budget(burst: u32, period_secs: u64) -> RateLimitBudget {
    RateLimitBudget { burst, period_secs }
}

/// Parses an override value the way the environment provider parses variables.
fn env_value(value: &str) -> figment::value::Value {
    value.parse().expect("parsing a figment value to be infallible")
}

fn header_source_with_trusted_proxies(trusted_proxies: &[&str]) -> serde_json::Value {
    json!({ "client_ip": { "source": "header", "trusted_proxies": trusted_proxies } })
}

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
        images: sample_image_storage_s3_config(),
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
            rate_limit: None,
            redirect_hosts: None,
            security: SecurityConfig::default(),
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

/// Sample S3 image storage configuration using default outbound deadlines.
fn sample_image_storage_s3_config() -> ImageStorageConfig {
    ImageStorageConfig::S3(ImageStorageConfigS3 {
        access_key_id: "s3-access-key-id".to_string(),
        bucket: "images".to_string(),
        region: "eu-west-1".to_string(),
        secret_access_key: "s3-sensitive-value".to_string(),

        connect_timeout_secs: DEFAULT_CONNECT_TIMEOUT_SECS,
        endpoint: Some("https://s3.example.test".to_string()),
        force_path_style: Some(true),
        request_timeout_secs: DEFAULT_REQUEST_TIMEOUT_SECS,
    })
}

fn sample_rate_limit_config() -> RateLimitConfig {
    RateLimitConfig {
        client_ip: ClientIpConfig::Peer(ClientIpPeerConfig {}),

        limits: RateLimitBudgets::default(),
        mode: RateLimitMode::Observe,
    }
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

fn trusted_proxies(count: u32) -> Vec<String> {
    (0..count)
        .map(|index| format!("10.{}.{}.0/24", index / 256, index % 256))
        .collect()
}
