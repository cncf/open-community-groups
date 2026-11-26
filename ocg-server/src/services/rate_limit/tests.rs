use std::{
    net::IpAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::http::{HeaderMap, HeaderName, HeaderValue};

use crate::{
    config::{
        ClientIpConfig, ClientIpHeaderConfig, ClientIpPeerConfig, RateLimitBudget,
        RateLimitBudgets, RateLimitConfig, RateLimitMode,
    },
    services::workers::BackgroundTasks,
};

use super::{
    IpLimit, Limit, LogInFailureLimit, RateLimited, RateLimiter, Verdict, budget_lines,
    client_ip::ClientKey, fold_username, setup,
};

#[test]
fn test_budget_lines_returns_every_limit_with_effective_budgets() {
    // Setup default budgets with two overrides
    let defaults = RateLimitBudgets::default();
    let budgets = RateLimitBudgets {
        log_in_failures: budget(3, 30),
        views: budget(7, 70),
        ..RateLimitBudgets::default()
    };

    // Check every limit is listed in order with its effective budget
    assert_eq!(
        budget_lines(&budgets),
        [
            (Limit::BadgeVerify, defaults.badge_verify),
            (Limit::ExploreSearch, defaults.explore_search),
            (Limit::ExternalAuth, defaults.external_auth),
            (Limit::LogIn, defaults.log_in),
            (Limit::LogInFailures, budget(3, 30)),
            (Limit::PasswordReset, defaults.password_reset),
            (Limit::ResendVerification, defaults.resend_verification),
            (Limit::SignUp, defaults.sign_up),
            (Limit::VerifyEmail, defaults.verify_email),
            (Limit::Views, budget(7, 70)),
        ]
    );
}

#[test]
fn test_fold_username() {
    // Setup labeled usernames with the expected folded bytes
    let cases = [
        ("ascii lowercase is unchanged", "alice", b"alice".to_vec()),
        ("ascii uppercase is lowercased", "AlIcE", b"alice".to_vec()),
        (
            "surrounding whitespace is trimmed",
            " \talice\n ",
            b"alice".to_vec(),
        ),
        ("kelvin sign folds to k", "\u{212A}ate", b"kate".to_vec()),
        (
            "dotted capital i folds to i",
            "\u{0130}van",
            b"ivan".to_vec(),
        ),
        ("dotless i folds to i", "\u{0131}van", b"ivan".to_vec()),
        (
            "combining dot above after i is dropped",
            "i\u{0307}van",
            b"ivan".to_vec(),
        ),
        (
            "combining dot above after capital i is dropped",
            "I\u{0307}van",
            b"ivan".to_vec(),
        ),
        (
            "combining dot above inside a non-ascii run is dropped",
            "\u{e9}\u{0307}\u{e8}x",
            b"\xffx".to_vec(),
        ),
        (
            "non-ascii character becomes a placeholder",
            "jos\u{e9}",
            b"jos\xff".to_vec(),
        ),
        (
            "non-ascii run becomes one placeholder",
            "\u{e9}\u{e8}x\u{fc}",
            b"\xffx\xff".to_vec(),
        ),
        ("empty username", "   ", Vec::new()),
    ];

    // Check each username folds as expected
    for (case, username, expected) in cases {
        assert_eq!(fold_username(username), expected, "{case}");
    }
}

#[test]
fn test_limit_from_ip_limit_and_name() {
    // Setup each IP limit with the limit and name it maps to
    let cases = [
        (IpLimit::BadgeVerify, Limit::BadgeVerify, "badge_verify"),
        (
            IpLimit::ExploreSearch,
            Limit::ExploreSearch,
            "explore_search",
        ),
        (IpLimit::ExternalAuth, Limit::ExternalAuth, "external_auth"),
        (IpLimit::LogIn, Limit::LogIn, "log_in"),
        (
            IpLimit::PasswordReset,
            Limit::PasswordReset,
            "password_reset",
        ),
        (
            IpLimit::ResendVerification,
            Limit::ResendVerification,
            "resend_verification",
        ),
        (IpLimit::SignUp, Limit::SignUp, "sign_up"),
        (IpLimit::VerifyEmail, Limit::VerifyEmail, "verify_email"),
        (IpLimit::Views, Limit::Views, "views"),
    ];

    // Check each IP limit converts and names as expected
    for (ip_limit, expected, name) in cases {
        assert_eq!(Limit::from(ip_limit), expected, "{name}");
        assert_eq!(expected.name(), name, "{name}");
    }

    // Check the limit without an IP counterpart is named too
    assert_eq!(Limit::LogInFailures.name(), "log_in_failures");
}

#[test]
fn test_log_in_failure_limit_is_clone_send_sync() {
    fn assert_extension<T: Clone + Send + Sync + 'static>() {}
    assert_extension::<LogInFailureLimit>();
}

#[test]
fn test_log_in_failure_limit_reserve_dropped_reservation_refunds() {
    for mode in [RateLimitMode::Enforce, RateLimitMode::Observe] {
        // Setup a failed log-in limit with a burst of one
        let now = Instant::now();
        let limiter = limiter(log_in_failures_budgets(budget(1, 60)), mode, now);
        let failures = limiter.log_in_failure_limit(client(1));

        // Reserve and drop attempts, as a successful log-in does
        for _ in 0..3 {
            let reservation = failures.reserve("alice", now).unwrap();
            assert!(reservation.holds_token, "{mode:?}");
        }

        // Check the token is still available and nothing was over the limit
        failures.reserve("alice", now).unwrap().record_failure();
        let window = limiter.take_window();
        let log_in_failures = window.limit(Limit::LogInFailures);
        assert_eq!(log_in_failures.requests, 4, "{mode:?}");
        assert_eq!(log_in_failures.over_limit, 0, "{mode:?}");
    }
}

#[test]
fn test_log_in_failure_limit_reserve_enforce_refuses_when_exhausted() {
    // Setup an enforcing failed log-in limit with a burst of two
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(2, 60)),
        RateLimitMode::Enforce,
        now,
    );
    let failures = limiter.log_in_failure_limit(client(1));

    // Record two failures
    failures.reserve("alice", now).unwrap().record_failure();
    failures.reserve("alice", now).unwrap().record_failure();

    // Check the next reservation is refused until one interval elapses
    assert_eq!(
        failures.reserve("alice", now).unwrap_err(),
        RateLimited {
            retry_after: Duration::from_secs(30)
        }
    );
    assert!(failures.reserve("alice", now + Duration::from_secs(30)).is_ok());

    // Check the refusal was counted over the limit
    let window = limiter.take_window();
    assert_eq!(window.limit(Limit::LogInFailures).over_limit, 1);
}

#[test]
fn test_log_in_failure_limit_reserve_folds_usernames_to_one_key() {
    let cases = [
        ("case", "Alice", "aLICE"),
        ("padding", "alice", "  alice\t"),
        ("unicode case variants", "jos\u{e9}", "JOS\u{c9}"),
        ("kelvin sign", "kate", "\u{212A}ate"),
        ("dotted capital i", "ivan", "\u{0130}van"),
        ("dotless i", "ivan", "\u{0131}van"),
        ("i with combining dot above", "ivan", "i\u{0307}van"),
        ("capital i with combining dot above", "ivan", "I\u{0307}van"),
        (
            "dotted capital i and its icu lowercase",
            "x\u{0130}y",
            "xi\u{0307}y",
        ),
    ];
    for (case, failed, variant) in cases {
        // Exhaust the budget of one spelling
        let now = Instant::now();
        let limiter = limiter(
            log_in_failures_budgets(budget(1, 60)),
            RateLimitMode::Enforce,
            now,
        );
        let failures = limiter.log_in_failure_limit(client(1));
        failures.reserve(failed, now).unwrap().record_failure();

        // Check the other spelling shares the exhausted budget
        assert!(failures.reserve(variant, now).is_err(), "{case}");
    }
}

#[test]
fn test_log_in_failure_limit_reserve_is_independent_across_clients_and_usernames() {
    // Setup an enforcing failed log-in limit and exhaust one client and username
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(1, 60)),
        RateLimitMode::Enforce,
        now,
    );
    let first_client = limiter.log_in_failure_limit(client(1));
    let second_client = limiter.log_in_failure_limit(client(2));
    first_client.reserve("alice", now).unwrap().record_failure();

    // Check only that client and username pair is limited
    assert!(first_client.reserve("alice", now).is_err());
    assert!(first_client.reserve("bob", now).is_ok());
    assert!(second_client.reserve("alice", now).is_ok());
}

#[test]
fn test_log_in_failure_limit_reserve_observe_denied_reservation_holds_no_token() {
    // Setup an observing failed log-in limit with an exhausted burst of one
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(1, 60)),
        RateLimitMode::Observe,
        now,
    );
    let failures = limiter.log_in_failure_limit(client(1));
    failures.reserve("alice", now).unwrap().record_failure();

    // Reserve over the limit and drop or confirm the token-less reservations
    let dropped = failures.reserve("alice", now).unwrap();
    assert!(!dropped.holds_token);
    drop(dropped);
    let confirmed = failures.reserve("alice", now).unwrap();
    assert!(!confirmed.holds_token);
    confirmed.record_failure();

    // Check nothing was refunded: the pair is still over the limit
    assert!(!failures.reserve("alice", now).unwrap().holds_token);
    let window = limiter.take_window();
    let log_in_failures = window.limit(Limit::LogInFailures);
    assert_eq!(log_in_failures.requests, 4);
    assert_eq!(log_in_failures.over_limit, 3);
}

#[test]
fn test_log_in_failure_limit_reserve_observe_success_leaves_failure_state_unchanged() {
    // Setup an observing failed log-in limit with a burst of two
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(2, 60)),
        RateLimitMode::Observe,
        now,
    );
    let failures = limiter.log_in_failure_limit(client(1));

    // Record one failure, then several successful log-ins
    failures.reserve("alice", now).unwrap().record_failure();
    for _ in 0..5 {
        drop(failures.reserve("alice", now).unwrap());
    }

    // Check exactly one token is left
    failures.reserve("alice", now).unwrap().record_failure();
    assert!(!failures.reserve("alice", now).unwrap().holds_token);
    let window = limiter.take_window();
    assert_eq!(window.limit(Limit::LogInFailures).over_limit, 1);
}

#[test]
fn test_log_in_failure_limit_reserve_record_failure_keeps_token() {
    for mode in [RateLimitMode::Enforce, RateLimitMode::Observe] {
        // Setup a failed log-in limit with a burst of one
        let now = Instant::now();
        let limiter = limiter(log_in_failures_budgets(budget(1, 60)), mode, now);
        let failures = limiter.log_in_failure_limit(client(1));

        // Record one failure, then attempt again
        failures.reserve("alice", now).unwrap().record_failure();
        let next = failures.reserve("alice", now);

        // Check the next attempt is over the limit: refused, or holding no token
        match mode {
            RateLimitMode::Enforce => assert!(next.is_err(), "{mode:?}"),
            RateLimitMode::Observe => assert!(!next.unwrap().holds_token, "{mode:?}"),
        }
        let window = limiter.take_window();
        assert_eq!(window.limit(Limit::LogInFailures).over_limit, 1, "{mode:?}");
    }
}

#[test]
fn test_log_in_failure_limit_reserve_statistics_grouped_by_client() {
    // Setup an enforcing failed log-in limit and two clients
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(1, 60)),
        RateLimitMode::Enforce,
        now,
    );
    let first_client = limiter.log_in_failure_limit(client(1));
    let second_client = limiter.log_in_failure_limit(client(2));

    // Fail with several usernames from the first client and succeed from the second
    for username in ["alice", "bob", "carol"] {
        first_client.reserve(username, now).unwrap().record_failure();
    }
    assert!(first_client.reserve("alice", now).is_err());
    for _ in 0..2 {
        drop(second_client.reserve("dave", now).unwrap());
    }

    // Check statistics are keyed by client alone and refunds are not subtracted
    let window = limiter.take_window();
    let log_in_failures = window.limit(Limit::LogInFailures);
    assert_eq!(log_in_failures.requests, 6);
    assert_eq!(log_in_failures.over_limit, 1);
    assert_eq!(log_in_failures.keys.entries.len(), 2);
    assert_eq!(log_in_failures.keys.entries[&client(1)].requests, 4);
    assert_eq!(log_in_failures.keys.entries[&client(1)].over_limit, 1);
    assert_eq!(log_in_failures.keys.entries[&client(2)].requests, 2);
    assert_eq!(log_in_failures.peak_burst_used_pct, 100);
}

#[test]
fn test_rate_limiter_check_enforce_rejects_over_limit() {
    // Setup an enforcing limiter with a views burst of two
    let now = Instant::now();
    let limiter = limiter(views_budgets(budget(2, 60)), RateLimitMode::Enforce, now);

    // Spend the burst, then exceed it
    let verdicts: Vec<_> = (0..3)
        .map(|_| limiter.check(IpLimit::Views, client(1), now))
        .collect();

    // Check the request over the limit is rejected until one interval elapses
    assert_eq!(
        verdicts,
        vec![
            Verdict::Allow,
            Verdict::Allow,
            Verdict::Reject {
                retry_after: Duration::from_secs(30)
            },
        ]
    );
    assert_eq!(
        limiter.check(IpLimit::Views, client(1), now + Duration::from_secs(30)),
        Verdict::Allow
    );

    // Check the statistics count every request and the rejection
    let window = limiter.take_window();
    let views = window.limit(Limit::Views);
    assert_eq!(views.requests, 4);
    assert_eq!(views.over_limit, 1);
    assert_eq!(views.keys.entries[&client(1)].over_limit, 1);
}

#[test]
fn test_rate_limiter_check_limits_are_independent() {
    // Setup an enforcing limiter and exhaust one limit for one client
    let now = Instant::now();
    let limiter = limiter(views_budgets(budget(1, 60)), RateLimitMode::Enforce, now);
    assert_eq!(
        limiter.check(IpLimit::Views, client(1), now),
        Verdict::Allow
    );

    // Check other clients and other limits are unaffected
    assert!(matches!(
        limiter.check(IpLimit::Views, client(1), now),
        Verdict::Reject { .. }
    ));
    assert_eq!(
        limiter.check(IpLimit::Views, client(2), now),
        Verdict::Allow
    );
    assert_eq!(
        limiter.check(IpLimit::LogIn, client(1), now),
        Verdict::Allow
    );
}

#[test]
fn test_rate_limiter_check_observe_allows_and_counts_over_limit() {
    // Setup an observing limiter with a views burst of two
    let now = Instant::now();
    let limiter = limiter(views_budgets(budget(2, 60)), RateLimitMode::Observe, now);

    // Send more requests than the burst
    let verdicts: Vec<_> = (0..5)
        .map(|_| limiter.check(IpLimit::Views, client(1), now))
        .collect();

    // Check nothing is rejected but the would-be rejections are reported and counted
    assert_eq!(
        verdicts,
        vec![
            Verdict::Allow,
            Verdict::Allow,
            Verdict::AllowOverLimit,
            Verdict::AllowOverLimit,
            Verdict::AllowOverLimit,
        ]
    );
    let window = limiter.take_window();
    let views = window.limit(Limit::Views);
    assert_eq!(views.requests, 5);
    assert_eq!(views.over_limit, 3);
    assert_eq!(views.peak_burst_used_pct, 100);
}

#[test]
fn test_rate_limiter_new_exposes_configuration() {
    // Setup a header source configuration with two trusted proxies
    let budgets = RateLimitBudgets {
        sign_up: budget(5, 50),
        ..RateLimitBudgets::default()
    };
    let cfg = RateLimitConfig {
        client_ip: header_cfg(&["10.0.0.0/8", "192.0.2.10"]),
        limits: budgets.clone(),
        mode: RateLimitMode::Enforce,
    };

    // Build the limiter
    let limiter = RateLimiter::new(&cfg, Instant::now()).unwrap();

    // Check the accessors report the configuration
    assert_eq!(limiter.budgets(), &budgets);
    assert_eq!(limiter.mode(), RateLimitMode::Enforce);
    assert_eq!(limiter.source_name(), "header");
    assert_eq!(limiter.trusted_proxy_count(), 2);
}

#[test]
fn test_rate_limiter_new_rejects_invalid_client_ip_config() {
    // Setup a configuration with an invalid trusted proxy
    let cfg = RateLimitConfig {
        client_ip: header_cfg(&["not-a-network"]),
        limits: RateLimitBudgets::default(),
        mode: RateLimitMode::Observe,
    };

    // Check building the limiter fails with the configuration error
    let Err(err) = RateLimiter::new(&cfg, Instant::now()) else {
        panic!("expected an invalid trusted proxy error");
    };
    assert_eq!(
        err.to_string(),
        "server.rate_limit.client_ip.trusted_proxies entry 'not-a-network' is not a valid CIDR or IP address"
    );
}

#[test]
fn test_rate_limiter_record_skipped_origin_check_counts_without_requests() {
    // Setup a limiter
    let now = Instant::now();
    let limiter = limiter(views_budgets(budget(1, 60)), RateLimitMode::Enforce, now);

    // Skip an origin-rejected request for a limit
    limiter.record_skipped_origin_check(IpLimit::SignUp);

    // Check the skip is counted apart from requests and leaves the budget untouched
    let window = limiter.take_window();
    let sign_up = window.limit(Limit::SignUp);
    assert_eq!(sign_up.skipped_origin_check, 1);
    assert_eq!(sign_up.requests, 0);
    assert!(sign_up.has_traffic());
}

#[test]
fn test_rate_limiter_resolve_client_records_client_ip_statistics() {
    // Setup limiters for the peer source and the header source with a trust list
    let now = Instant::now();
    let peer_limiter = limiter(views_budgets(budget(1, 60)), RateLimitMode::Observe, now);
    let header_limiter = RateLimiter::new(
        &RateLimitConfig {
            client_ip: header_cfg(&["10.0.0.0/8"]),
            limits: RateLimitBudgets::default(),
            mode: RateLimitMode::Observe,
        },
        now,
    )
    .unwrap();

    // Resolve requests with every outcome
    let no_header = HeaderMap::new();
    let peer_cases = [
        (
            "peer used",
            Some(ip("203.0.113.7")),
            Some(client_key("203.0.113.7")),
        ),
        (
            "internal peer",
            Some(ip("192.168.1.5")),
            Some(client_key("192.168.1.5")),
        ),
        ("no peer information", None, None),
    ];
    for (case, peer, expected) in peer_cases {
        assert_eq!(
            peer_limiter.resolve_client(peer, &no_header),
            expected,
            "{case}"
        );
    }
    let trusted_peer = Some(ip("10.0.0.1"));
    let header_cases = [
        (
            "header used",
            trusted_peer,
            vec!["203.0.113.9"],
            Some(client_key("203.0.113.9")),
        ),
        (
            "internal client",
            trusted_peer,
            vec!["172.16.0.4"],
            Some(client_key("172.16.0.4")),
        ),
        ("all entries trusted", trusted_peer, vec!["10.1.1.1"], None),
        ("header missing", trusted_peer, vec![], None),
        ("no peer information", None, vec!["203.0.113.9"], None),
        ("unparseable entry", trusted_peer, vec!["unknown"], None),
        (
            "untrusted peer",
            Some(ip("198.51.100.1")),
            vec!["203.0.113.9"],
            None,
        ),
    ];
    for (case, peer, lines, expected) in header_cases {
        assert_eq!(
            header_limiter.resolve_client(peer, &headers(&lines)),
            expected,
            "{case}"
        );
    }

    // Check the peer source counters
    let window = peer_limiter.take_window();
    let client_ip = &window.client_ip;
    assert_eq!(client_ip.peer_used, 2);
    assert_eq!(client_ip.header_used, 0);
    assert_eq!(client_ip.internal_clients, 1);
    assert_eq!(
        client_ip.internal_client_addresses.entries[&client_key("192.168.1.5")],
        1
    );
    assert_eq!(client_ip.unresolved_no_peer_info, 1);
    assert_eq!(client_ip.unresolved(), 1);
    assert_eq!(window.proxy.peers.entries.len(), 2);
    assert!(!window.proxy.peers.entries[&ip("203.0.113.7")].is_trusted_proxy);

    // Check the header source counters, each unresolved reason in its own field
    let window = header_limiter.take_window();
    let client_ip = &window.client_ip;
    assert_eq!(client_ip.peer_used, 0);
    assert_eq!(client_ip.header_used, 2);
    assert_eq!(client_ip.internal_clients, 1);
    assert_eq!(client_ip.unresolved_all_entries_trusted, 1);
    assert_eq!(client_ip.unresolved_header_missing, 1);
    assert_eq!(client_ip.unresolved_no_peer_info, 1);
    assert_eq!(client_ip.unresolved_unparseable_entry, 1);
    assert_eq!(client_ip.unresolved_untrusted_peer, 1);
    assert!(window.proxy.peers.entries[&ip("10.0.0.1")].is_trusted_proxy);
    assert_eq!(window.proxy.peers.entries[&ip("10.0.0.1")].requests, 5);
    assert!(!window.proxy.peers.entries[&ip("198.51.100.1")].is_trusted_proxy);

    // Check resolution alone counts no request for any limit
    for limit in Limit::ALL {
        assert!(!window.limit(limit).has_traffic(), "{}", limit.name());
    }
}

#[test]
fn test_rate_limiter_take_window_reports_log_in_failure_evictions() {
    // Setup an observing limiter whose failed log-in budget outlasts the test
    let now = Instant::now();
    let limiter = limiter(
        log_in_failures_budgets(budget(10, 900)),
        RateLimitMode::Observe,
        now,
    );
    let failures = limiter.log_in_failure_limit(client(1));

    // Record more distinct failed usernames than the store can track
    for index in 0..60_000 {
        failures
            .reserve(&format!("user{index}"), now)
            .unwrap()
            .record_failure();
    }

    // Check the evictions are reported once
    let window = limiter.take_window();
    let log_in_failures = window.limit(Limit::LogInFailures);
    assert!(log_in_failures.evicted_store_full > 0);
    assert_eq!(log_in_failures.untracked_store_full, 0);
    assert_eq!(log_in_failures.keys.entries.len(), 1);
    assert_eq!(
        limiter.take_window().limit(Limit::LogInFailures).evicted_store_full,
        0
    );
}

#[test]
fn test_rate_limiter_take_window_starts_empty_window() {
    // Setup a limiter with traffic in the current window
    let now = Instant::now();
    let limiter = limiter(views_budgets(budget(1, 60)), RateLimitMode::Enforce, now);
    limiter.resolve_client(Some(ip("203.0.113.7")), &HeaderMap::new());
    limiter.check(IpLimit::Views, client(1), now);

    // Take the window twice
    let first = limiter.take_window();
    let second = limiter.take_window();

    // Check the traffic is reported once
    assert!(!first.is_empty());
    assert_eq!(first.limit(Limit::Views).requests, 1);
    assert!(second.is_empty());
}

#[tokio::test]
async fn test_setup_with_config_returns_limiter_and_starts_summary_worker() {
    // Setup a configuration and background tasks
    let cfg = RateLimitConfig {
        client_ip: header_cfg(&["10.0.0.0/8"]),
        limits: views_budgets(budget(7, 70)),
        mode: RateLimitMode::Enforce,
    };
    let background_tasks = BackgroundTasks::new(Duration::from_secs(5));

    // Set up rate limiting
    let rate_limiter = setup(Some(&cfg), &background_tasks).unwrap().unwrap();

    // Check the limiter follows the configuration and the summary worker runs
    assert_eq!(rate_limiter.budgets(), &cfg.limits);
    assert_eq!(rate_limiter.mode(), RateLimitMode::Enforce);
    assert_eq!(rate_limiter.source_name(), "header");
    assert_eq!(rate_limiter.trusted_proxy_count(), 1);
    let workers = background_tasks.registry().snapshot();
    assert_eq!(
        workers.keys().copied().collect::<Vec<_>>(),
        ["rate-limit-summary"]
    );
    assert_eq!(workers["rate-limit-summary"].running, 1);

    // Check the worker stops on shutdown as an expected stop
    let registry = background_tasks.registry();
    background_tasks.shutdown().await;
    let worker = &registry.snapshot()["rate-limit-summary"];
    assert_eq!(worker.running, 0);
    assert_eq!(worker.unexpected_exits, []);
}

#[tokio::test]
async fn test_setup_without_config_starts_nothing() {
    // Set up rate limiting without a configuration
    let background_tasks = BackgroundTasks::new(Duration::from_secs(5));
    let rate_limiter = setup(None, &background_tasks).unwrap();

    // Check no limiter is built and no worker is registered
    assert!(rate_limiter.is_none());
    assert!(background_tasks.registry().snapshot().is_empty());
}

// Helpers.

/// Returns a budget.
fn budget(burst: u32, period_secs: u64) -> RateLimitBudget {
    RateLimitBudget { burst, period_secs }
}

/// Returns a distinct IPv4 client key for an index.
fn client(index: u8) -> ClientKey {
    ClientKey::V4([203, 0, 113, index])
}

/// Returns the client key of an address.
fn client_key(address: &str) -> ClientKey {
    ClientKey::from(ip(address))
}

/// Returns an `x-forwarded-for` header source configuration.
fn header_cfg(trusted_proxies: &[&str]) -> ClientIpConfig {
    ClientIpConfig::Header(ClientIpHeaderConfig {
        header: "x-forwarded-for".to_string(),
        trusted_proxies: trusted_proxies.iter().map(ToString::to_string).collect(),
    })
}

/// Returns headers with one `x-forwarded-for` line per entry.
fn headers(lines: &[&str]) -> HeaderMap {
    let mut headers = HeaderMap::new();
    for line in lines {
        headers.append(
            HeaderName::from_static("x-forwarded-for"),
            HeaderValue::from_str(line).unwrap(),
        );
    }
    headers
}

/// Parses an address.
fn ip(address: &str) -> IpAddr {
    address.parse().unwrap()
}

/// Builds a shared limiter from budgets, using the peer source.
fn limiter(limits: RateLimitBudgets, mode: RateLimitMode, now: Instant) -> Arc<RateLimiter> {
    let cfg = RateLimitConfig {
        client_ip: ClientIpConfig::Peer(ClientIpPeerConfig {}),
        limits,
        mode,
    };
    Arc::new(RateLimiter::new(&cfg, now).unwrap())
}

/// Returns default budgets with the failed log-in budget replaced.
fn log_in_failures_budgets(log_in_failures: RateLimitBudget) -> RateLimitBudgets {
    RateLimitBudgets {
        log_in_failures,
        ..RateLimitBudgets::default()
    }
}

/// Returns default budgets with the views budget replaced.
fn views_budgets(views: RateLimitBudget) -> RateLimitBudgets {
    RateLimitBudgets {
        views,
        ..RateLimitBudgets::default()
    }
}
