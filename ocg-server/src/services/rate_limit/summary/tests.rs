use std::{
    net::IpAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::http::{HeaderMap, HeaderName, HeaderValue};
use tokio::time::timeout;
use tokio_util::sync::CancellationToken;
use tracing::Level;
use uuid::Uuid;

use crate::{
    config::{
        ClientIpConfig, ClientIpHeaderConfig, ClientIpPeerConfig, RateLimitBudgets,
        RateLimitConfig, RateLimitMode,
    },
    services::rate_limit::{
        IpLimit, Limit, RateLimiter,
        client_ip::ClientKey,
        stats::{
            ClientIpWindow, KeyCounts, LimitKey, LimitWindow, MAX_CHAIN_LENGTH, PeerCounts,
            WindowSnapshot,
        },
    },
};

use super::{Counted, KeyShare, Reporter, SUMMARY_WINDOW, SummaryWarning, build_report, join};

#[test]
fn test_build_report_client_ip_summary_present_for_idle_window() {
    // Setup an idle window
    let mut window = WindowSnapshot::default();
    window.duration = Duration::from_millis(300_400);

    // Build the report
    let report = build_report(&window, RateLimitMode::Enforce, "header");

    // Check only the client IP summary is reported
    let client_ip = &report.client_ip;
    assert_eq!(client_ip.level, Level::INFO);
    assert_eq!(client_ip.mode, RateLimitMode::Enforce);
    assert_eq!(client_ip.source, "header");
    assert_eq!(client_ip.window_secs, 300);
    assert_eq!(client_ip.peer_used, 0);
    assert_eq!(client_ip.header_used, 0);
    assert!(report.proxy.is_none());
    assert_eq!(report.limits, []);
    assert_eq!(report.warnings, []);
}

#[test]
fn test_build_report_client_ip_summary_warns_when_unresolved() {
    // Setup labeled client IP windows with the expected summary level
    let cases = [
        (
            "every request resolved",
            ClientIpWindow {
                header_used: 10,
                peer_used: 10,
                ..ClientIpWindow::default()
            },
            Level::INFO,
        ),
        (
            "all entries trusted",
            ClientIpWindow {
                unresolved_all_entries_trusted: 1,
                ..ClientIpWindow::default()
            },
            Level::WARN,
        ),
        (
            "header missing",
            ClientIpWindow {
                unresolved_header_missing: 1,
                ..ClientIpWindow::default()
            },
            Level::WARN,
        ),
        (
            "no peer information",
            ClientIpWindow {
                unresolved_no_peer_info: 1,
                ..ClientIpWindow::default()
            },
            Level::WARN,
        ),
        (
            "unparseable entry",
            ClientIpWindow {
                unresolved_unparseable_entry: 1,
                ..ClientIpWindow::default()
            },
            Level::WARN,
        ),
        (
            "untrusted peer",
            ClientIpWindow {
                unresolved_untrusted_peer: 1,
                ..ClientIpWindow::default()
            },
            Level::WARN,
        ),
    ];

    for (case, client_ip, expected) in cases {
        // Build the report for a window with only client IP statistics
        let window = window_with_client_ip(client_ip.clone());
        let report = build_report(&window, RateLimitMode::Observe, "peer");

        // Check the summary level and its unresolved counts
        let summary = &report.client_ip;
        assert_eq!(summary.level, expected, "{case}");
        assert_eq!(
            summary.unresolved_all_entries_trusted, client_ip.unresolved_all_entries_trusted,
            "{case}"
        );
        assert_eq!(
            summary.unresolved_header_missing, client_ip.unresolved_header_missing,
            "{case}"
        );
        assert_eq!(
            summary.unresolved_no_peer_info, client_ip.unresolved_no_peer_info,
            "{case}"
        );
        assert_eq!(
            summary.unresolved_unparseable_entry, client_ip.unresolved_unparseable_entry,
            "{case}"
        );
        assert_eq!(
            summary.unresolved_untrusted_peer, client_ip.unresolved_untrusted_peer,
            "{case}"
        );
    }
}

#[test]
fn test_build_report_dominant_key_warning_ignores_overflow_bucket() {
    // Setup a capped limit whose overflow bucket holds most requests
    let mut views = LimitWindow {
        requests: 1_000,
        ..LimitWindow::default()
    };
    views.keys.entries.insert(key(1), key_counts(0, 400));
    views.keys.is_capped = true;
    views.keys.other = key_counts(0, 600);
    let window = window_with_limit(Limit::Views, views);

    // Build the report
    let report = build_report(&window, RateLimitMode::Observe, "peer");

    // Check no tracked key dominates and the overflow bucket is in the denominator
    assert_eq!(report.warnings, []);
    let summary = &report.limits[0];
    assert!(summary.distinct_keys_capped);
    assert_eq!(
        summary.top_keys,
        vec![KeyShare {
            key: "203.0.113.x".to_string(),
            requests: 400,
            share_permille: 400,
        }]
    );
}

#[test]
fn test_build_report_dominant_key_warning_threshold() {
    let cases = [
        ("half of the minimum requests", 100, 50, true),
        ("just below half", 100, 49, false),
        ("half below the minimum requests", 98, 49, false),
        ("every request from one key", 400, 400, true),
    ];
    for (case, requests, top_requests, expected) in cases {
        // Setup a limit whose top key makes `top_requests` and the rest are spread
        let mut views = LimitWindow {
            requests,
            ..LimitWindow::default()
        };
        views.keys.entries.insert(key(1), key_counts(0, top_requests));
        for index in 0..requests - top_requests {
            let other = key(u8::try_from(index + 2).unwrap());
            views.keys.entries.insert(other, key_counts(0, 1));
        }
        let window = window_with_limit(Limit::Views, views);

        // Build the report and check the warning
        let report = build_report(&window, RateLimitMode::Observe, "peer");
        let warning = SummaryWarning::DominantKey {
            key: KeyShare {
                key: "203.0.113.x".to_string(),
                requests: top_requests,
                share_permille: top_requests * 1_000 / requests,
            },
            limit: Limit::Views,
        };
        assert_eq!(report.warnings.contains(&warning), expected, "{case}");
        assert_eq!(report.warnings.len(), usize::from(expected), "{case}");
        assert!(
            report.warnings.iter().all(|warning| warning.level() == Level::WARN),
            "{case}"
        );
    }
}

#[test]
fn test_build_report_entries_left_of_client_warning_threshold() {
    // Setup labeled header resolution counts with whether the warning is expected
    let cases = [
        ("more than half", 100, 51, true),
        ("exactly half", 100, 50, false),
        ("every request", 10, 10, true),
        ("no header-resolved request", 0, 0, false),
    ];

    for (case, header_used, entries_left_of_client, expected) in cases {
        // Build the report for a window with those counts
        let window = window_with_client_ip(ClientIpWindow {
            entries_left_of_client,
            header_used,
            ..ClientIpWindow::default()
        });
        let report = build_report(&window, RateLimitMode::Observe, "header");

        // Check the warning and that the client IP summary stays informational
        let warning = SummaryWarning::EntriesLeftOfClient {
            entries_left_of_client,
            header_used,
        };
        assert_eq!(report.warnings.contains(&warning), expected, "{case}");
        assert_eq!(report.warnings.len(), usize::from(expected), "{case}");
        assert_eq!(report.client_ip.level, Level::INFO, "{case}");
    }
}

#[test]
fn test_build_report_internal_clients_warning_lists_addresses_in_full() {
    // Setup a limiter that sees internal peers with distinct request counts
    let now = Instant::now();
    let limiter = limiter(peer_cfg(), RateLimitMode::Observe, now);
    let peers = [
        ("10.0.0.1", 1),
        ("10.0.0.2", 7),
        ("10.0.0.3", 3),
        ("10.0.0.4", 3),
        ("10.0.0.5", 5),
        ("10.0.0.6", 6),
        ("fd00:1:2:3::9", 4),
    ];
    for (peer, requests) in peers {
        for _ in 0..requests {
            let client = limiter.resolve_client(Some(ip(peer)), &HeaderMap::new()).unwrap();
            limiter.check(IpLimit::Views, client, now);
        }
    }

    // Build the report from the taken window
    let report = build_report(&limiter.take_window(), RateLimitMode::Observe, "peer");

    // Check the five most frequent internal addresses are listed in full
    assert_eq!(
        report.warnings,
        vec![SummaryWarning::InternalClients {
            internal_client_addresses: vec![
                counted("10.0.0.2", 7),
                counted("10.0.0.6", 6),
                counted("10.0.0.5", 5),
                counted("fd00:1:2:3::/64", 4),
                counted("10.0.0.3", 3),
            ],
            internal_clients: 29,
            resolved_clients: 29,
        }]
    );

    // Check the same clients stay masked in the limit's top keys
    let top_keys: Vec<&str> =
        report.limits[0].top_keys.iter().map(|key| key.key.as_str()).collect();
    assert_eq!(
        top_keys,
        ["10.0.0.x", "10.0.0.x", "10.0.0.x", "fd00:1:2::", "10.0.0.x"]
    );
}

#[test]
fn test_build_report_internal_clients_warning_threshold() {
    let cases = [
        ("five percent", 95, 5, true),
        ("below five percent", 96, 4, false),
        ("every client internal", 0, 3, true),
        ("no resolved client", 0, 0, false),
    ];
    for (case, external_clients, internal_clients, expected) in cases {
        // Setup header and peer resolutions with some internal clients
        let mut client_ip = ClientIpWindow {
            header_used: external_clients,
            internal_clients,
            peer_used: internal_clients,
            ..ClientIpWindow::default()
        };
        if internal_clients > 0 {
            client_ip
                .internal_client_addresses
                .entries
                .insert(ClientKey::V4([10, 0, 0, 1]), internal_clients);
        }
        let window = window_with_client_ip(client_ip);

        // Build the report and check the warning
        let report = build_report(&window, RateLimitMode::Observe, "header");
        let warning = SummaryWarning::InternalClients {
            internal_client_addresses: vec![counted("10.0.0.1", internal_clients)],
            internal_clients,
            resolved_clients: external_clients + internal_clients,
        };
        assert_eq!(report.warnings.contains(&warning), expected, "{case}");
        assert_eq!(report.warnings.len(), usize::from(expected), "{case}");
    }
}

#[test]
fn test_build_report_leaves_out_idle_limits() {
    // Setup one limit with requests, one with only cross-origin skips and the rest idle
    let mut window = WindowSnapshot::default();
    let views = window.limit_mut(Limit::Views);
    views.requests = 3;
    views.over_limit = 1;
    views.peak_burst_used_pct = 100;
    views.keys.entries.insert(key(1), key_counts(1, 2));
    views.keys.entries.insert(key(2), key_counts(0, 1));
    window.limit_mut(Limit::SignUp).skipped_origin_check = 2;

    // Build the report
    let report = build_report(&window, RateLimitMode::Enforce, "peer");

    // Check only the limits with traffic are reported, in limit order
    let limits: Vec<Limit> = report.limits.iter().map(|limit| limit.limit).collect();
    assert_eq!(limits, [Limit::SignUp, Limit::Views]);

    // Check the origin-check-skip only limit
    let sign_up = &report.limits[0];
    assert_eq!(sign_up.level, Level::INFO);
    assert_eq!(sign_up.requests, 0);
    assert_eq!(sign_up.skipped_origin_check, 2);
    assert_eq!(sign_up.top_keys, []);

    // Check the limit with requests
    let views = &report.limits[1];
    assert_eq!(views.distinct_keys, 2);
    assert!(!views.distinct_keys_capped);
    assert_eq!(views.level, Level::INFO);
    assert_eq!(views.mode, RateLimitMode::Enforce);
    assert_eq!(views.over_limit, 1);
    assert_eq!(views.over_limit_keys, 1);
    assert_eq!(views.peak_burst_used_pct, 100);
    assert_eq!(views.requests, 3);
    assert_eq!(views.skipped_origin_check, 0);
    assert_eq!(
        views.top_keys,
        vec![
            key_share("203.0.113.x", 2, 666),
            key_share("203.0.113.x", 1, 333),
        ]
    );
}

#[test]
fn test_build_report_limit_summary_warns_when_store_full() {
    // Setup labeled store-full counts with the expected summary level
    let cases = [
        ("store not full", 0, 0, Level::INFO),
        ("untracked keys", 3, 0, Level::WARN),
        ("evicted keys", 0, 2, Level::WARN),
    ];

    for (case, untracked_store_full, evicted_store_full, expected) in cases {
        // Build the report for a window in which only the failed log-in limit has traffic
        let window = window_with_limit(
            Limit::LogInFailures,
            LimitWindow {
                evicted_store_full,
                requests: 5,
                untracked_store_full,
                ..LimitWindow::default()
            },
        );
        let report = build_report(&window, RateLimitMode::Observe, "peer");

        // Check the summary level and its store-full counts
        let summary = &report.limits[0];
        assert_eq!(summary.limit, Limit::LogInFailures, "{case}");
        assert_eq!(summary.level, expected, "{case}");
        assert_eq!(summary.untracked_store_full, untracked_store_full, "{case}");
        assert_eq!(summary.evicted_store_full, evicted_store_full, "{case}");
    }
}

#[test]
fn test_build_report_peer_display() {
    let cases = [
        (
            "peer source",
            peer_cfg(),
            vec![
                counted("10.0.0.7", 3),
                counted("198.51.100.x", 2),
                counted("203.0.113.x", 2),
            ],
        ),
        (
            "header source with an empty trust list",
            header_cfg(&[]),
            vec![
                counted("10.0.0.7", 3),
                counted("198.51.100.x", 2),
                counted("203.0.113.x", 2),
            ],
        ),
        (
            "header source with a trust list",
            header_cfg(&["198.51.100.0/24"]),
            vec![
                counted("10.0.0.7", 3),
                counted("198.51.100.10", 2),
                counted("203.0.113.x", 2),
            ],
        ),
    ];
    for (case, client_ip, expected) in cases {
        // Setup traffic from an internal peer, a public peer and a peer in the trust list
        let limiter = limiter(client_ip, RateLimitMode::Observe, Instant::now());
        let headers = forwarded_for("192.0.2.1");
        let peers = [("10.0.0.7", 3), ("198.51.100.10", 2), ("203.0.113.7", 2)];
        for (peer, requests) in peers {
            for _ in 0..requests {
                limiter.resolve_client(Some(ip(peer)), &headers);
            }
        }

        // Build the report from the taken window
        let source = limiter.source_name();
        let report = build_report(&limiter.take_window(), RateLimitMode::Observe, source);

        // Check trusted and internal peers are in full and other peers masked
        let proxy = report.proxy.expect(case);
        assert_eq!(proxy.top_peers, expected, "{case}");
        assert_eq!(proxy.distinct_peers, 3, "{case}");
        assert!(!proxy.distinct_peers_capped, "{case}");
    }
}

#[test]
fn test_build_report_proxy_summary_encodes_chain_lengths() {
    // Setup peers and header shapes, including an open-ended chain length bucket
    let mut window = WindowSnapshot::default();
    window.proxy.chain_lengths[1] = 1_200;
    window.proxy.chain_lengths[2] = 40;
    window.proxy.chain_lengths[MAX_CHAIN_LENGTH] = 1;
    window.proxy.multiple_header_lines = 4;
    window
        .proxy
        .peers
        .entries
        .insert(ip("10.0.0.7"), peer_counts(true, 1_834));
    window
        .proxy
        .peers
        .entries
        .insert(ip("10.0.0.8"), peer_counts(true, 1_790));
    window.proxy.peers.is_capped = true;

    // Build the report
    let report = build_report(&window, RateLimitMode::Observe, "header");

    // Check the proxy summary and its log field encodings
    let proxy = report.proxy.unwrap();
    assert_eq!(join(&proxy.top_peers), "10.0.0.7=1834 10.0.0.8=1790");
    assert_eq!(join(&proxy.chain_lengths), "1=1200 2=40 8+=1");
    assert_eq!(proxy.distinct_peers, 2);
    assert!(proxy.distinct_peers_capped);
    assert_eq!(proxy.multiple_header_lines, 4);
}

#[test]
fn test_build_report_top_keys_breaks_ties_by_key() {
    // Setup seven keys, several of them tied
    let mut views = LimitWindow {
        requests: 20,
        ..LimitWindow::default()
    };
    let keys = [
        (LimitKey::Client(ClientKey::V4([198, 51, 100, 1])), 2),
        (LimitKey::Client(ClientKey::V4([203, 0, 113, 9])), 5),
        (LimitKey::Client(ClientKey::V4([192, 0, 2, 1])), 3),
        (
            LimitKey::Client(ClientKey::V6Prefix([0x20, 0x01, 0x0d, 0xb8, 0, 1, 0, 0])),
            3,
        ),
        (LimitKey::Client(ClientKey::V4([203, 0, 113, 1])), 3),
        (LimitKey::Client(ClientKey::V4([192, 0, 2, 9])), 2),
        (LimitKey::Client(ClientKey::V4([10, 0, 0, 1])), 2),
    ];
    for (key, requests) in keys {
        views.keys.entries.insert(key, key_counts(0, requests));
    }
    let window = window_with_limit(Limit::ExploreSearch, views);

    // Build the report
    let report = build_report(&window, RateLimitMode::Observe, "peer");

    // Check the five keys with most requests, ties in ascending key order
    assert_eq!(
        join(&report.limits[0].top_keys),
        "203.0.113.x=5(25.0%) 192.0.2.x=3(15.0%) 203.0.113.x=3(15.0%) 2001:db8:1::=3(15.0%) \
         10.0.0.x=2(10.0%)"
    );
}

#[test]
fn test_build_report_unresolved_requests_absent_from_limits() {
    // Setup a limiter that cannot resolve a request without peer information
    let limiter = limiter(peer_cfg(), RateLimitMode::Enforce, Instant::now());
    assert_eq!(limiter.resolve_client(None, &HeaderMap::new()), None);

    // Build the report from the taken window
    let report = build_report(&limiter.take_window(), RateLimitMode::Enforce, "peer");

    // Check the request is only in the client IP summary
    assert_eq!(report.client_ip.unresolved_no_peer_info, 1);
    assert_eq!(report.client_ip.level, Level::WARN);
    assert_eq!(report.limits, []);
    assert!(report.proxy.is_none());
}

#[test]
fn test_build_report_user_keyed_limit_omits_top_keys_and_dominant_key_warning() {
    // Setup a user-keyed limit where one user accounts for every request above the threshold
    let user_id = Uuid::from_u128(42);
    let mut uploads = LimitWindow {
        requests: 200,
        over_limit: 5,
        ..LimitWindow::default()
    };
    uploads
        .keys
        .entries
        .insert(LimitKey::User(user_id), key_counts(5, 200));
    let window = window_with_limit(Limit::ImageUploads, uploads);

    // Build the report
    let report = build_report(&window, RateLimitMode::Enforce, "header");

    // Check aggregate counts stay intact while account IDs and IP/NAT warnings are omitted
    assert_eq!(report.warnings, []);
    let summary = &report.limits[0];
    assert_eq!(summary.limit, Limit::ImageUploads);
    assert_eq!(summary.level, Level::INFO);
    assert_eq!(summary.distinct_keys, 1);
    assert_eq!(summary.over_limit, 5);
    assert_eq!(summary.over_limit_keys, 1);
    assert_eq!(summary.requests, 200);
    assert_eq!(summary.top_keys, []);
}

#[test]
fn test_key_share_display_formats_share_with_one_decimal() {
    // Setup labeled key shares with the expected display
    let cases = [
        (
            "full share",
            key_share("203.0.113.x", 10, 1_000),
            "203.0.113.x=10(100.0%)",
        ),
        (
            "partial share",
            key_share("2001:db8:1234::", 7, 333),
            "2001:db8:1234::=7(33.3%)",
        ),
        (
            "tiny share",
            key_share("192.0.2.x", 1, 0),
            "192.0.2.x=1(0.0%)",
        ),
    ];

    // Check each key share displays as expected
    for (case, key_share, expected) in cases {
        assert_eq!(key_share.to_string(), expected, "{case}");
    }
}

#[tokio::test(start_paused = true)]
async fn test_reporter_run_reports_final_window_when_cancelled_after_first_report() {
    // Setup a reporter and let it report its first window
    let now = Instant::now();
    let (limiter, reporter) = reporter(now);
    let run = reporter.run();
    tokio::pin!(run);
    assert!(
        timeout(SUMMARY_WINDOW + Duration::from_secs(1), &mut run)
            .await
            .is_err()
    );

    // Record traffic during the second window, then cancel
    limiter.check(IpLimit::Views, ClientKey::V4([203, 0, 113, 7]), now);
    reporter.cancellation_token.cancel();
    run.await;

    // Check the final window was taken
    assert!(limiter.take_window().is_empty());
}

#[tokio::test(start_paused = true)]
async fn test_reporter_run_reports_final_window_when_cancelled_during_first_window() {
    // Setup a reporter with traffic recorded in its first window
    let now = Instant::now();
    let (limiter, reporter) = reporter(now);
    limiter.check(IpLimit::Views, ClientKey::V4([203, 0, 113, 7]), now);

    // Cancel before the first window elapses
    reporter.cancellation_token.cancel();
    reporter.run().await;

    // Check the final window was taken
    assert!(limiter.take_window().is_empty());
}

#[tokio::test(start_paused = true)]
async fn test_reporter_run_reports_only_after_first_window() {
    // Setup a reporter with traffic recorded in its first window
    let now = Instant::now();
    let (limiter, reporter) = reporter(now);
    limiter.check(IpLimit::Views, ClientKey::V4([203, 0, 113, 7]), now);
    let run = reporter.run();
    tokio::pin!(run);

    // Run until just before the first window elapses
    assert!(
        timeout(
            SUMMARY_WINDOW.saturating_sub(Duration::from_secs(1)),
            &mut run
        )
        .await
        .is_err()
    );

    // Check the window was not taken, then record traffic again
    assert_eq!(limiter.take_window().limit(Limit::Views).requests, 1);
    limiter.check(IpLimit::Views, ClientKey::V4([203, 0, 113, 7]), now);

    // Run past the end of the first window
    assert!(timeout(Duration::from_secs(2), &mut run).await.is_err());

    // Check the reporter took the window
    assert!(limiter.take_window().is_empty());
}

// Helpers.

/// Returns a labeled request count.
fn counted(label: &str, requests: u64) -> Counted {
    Counted {
        label: label.to_string(),
        requests,
    }
}

/// Returns headers with one `x-forwarded-for` line.
fn forwarded_for(line: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        HeaderName::from_static("x-forwarded-for"),
        HeaderValue::from_str(line).unwrap(),
    );
    headers
}

/// Returns an `x-forwarded-for` header source configuration.
fn header_cfg(trusted_proxies: &[&str]) -> ClientIpConfig {
    ClientIpConfig::Header(ClientIpHeaderConfig {
        header: "x-forwarded-for".to_string(),
        trusted_proxies: trusted_proxies.iter().map(ToString::to_string).collect(),
    })
}

/// Parses an address.
fn ip(address: &str) -> IpAddr {
    address.parse().unwrap()
}

/// Returns a distinct IPv4 client limit key in `203.0.113.0/24` for an index.
fn key(index: u8) -> LimitKey {
    LimitKey::Client(ClientKey::V4([203, 0, 113, index]))
}

/// Returns the request counts of one key.
fn key_counts(over_limit: u64, requests: u64) -> KeyCounts {
    KeyCounts {
        over_limit,
        requests,
    }
}

/// Returns a masked key with its request count and share.
fn key_share(key: &str, requests: u64, share_permille: u64) -> KeyShare {
    KeyShare {
        key: key.to_string(),
        requests,
        share_permille,
    }
}

/// Builds a shared limiter with default budgets.
fn limiter(client_ip: ClientIpConfig, mode: RateLimitMode, now: Instant) -> Arc<RateLimiter> {
    let cfg = RateLimitConfig {
        client_ip,
        limits: RateLimitBudgets::default(),
        mode,
    };
    Arc::new(RateLimiter::new(&cfg, now).unwrap())
}

/// Returns a peer source configuration.
fn peer_cfg() -> ClientIpConfig {
    ClientIpConfig::Peer(ClientIpPeerConfig {})
}

/// Returns the request counts of one peer.
fn peer_counts(is_trusted_proxy: bool, requests: u64) -> PeerCounts {
    PeerCounts {
        is_trusted_proxy,
        requests,
    }
}

/// Builds an observing limiter and a reporter for it with a fresh
/// cancellation token.
fn reporter(now: Instant) -> (Arc<RateLimiter>, Reporter) {
    let limiter = limiter(peer_cfg(), RateLimitMode::Observe, now);
    let reporter = Reporter {
        cancellation_token: CancellationToken::new(),
        rate_limiter: Arc::clone(&limiter),
    };
    (limiter, reporter)
}

/// Returns a window with only client IP statistics.
fn window_with_client_ip(client_ip: ClientIpWindow) -> WindowSnapshot {
    let mut window = WindowSnapshot::default();
    window.client_ip = client_ip;
    window
}

/// Returns a window in which only one limit has statistics.
fn window_with_limit(limit: Limit, limit_window: LimitWindow) -> WindowSnapshot {
    let mut window = WindowSnapshot::default();
    *window.limit_mut(limit) = limit_window;
    window
}
