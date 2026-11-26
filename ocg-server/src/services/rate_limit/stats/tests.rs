use std::{
    collections::HashMap,
    net::{IpAddr, Ipv4Addr},
    time::{Duration, Instant},
};

use uuid::Uuid;

use crate::services::rate_limit::{
    Limit,
    client_ip::{
        ClientKey, HeaderShape, Resolution, ResolvedClient, ResolvedVia, UnresolvedReason,
    },
    store::Decision,
};

use super::{
    CappedMap, ClientIpWindow, KeyCounts, LimitKey, MAX_CHAIN_LENGTH,
    MAX_INTERNAL_CLIENT_ADDRESSES, MAX_KEYS_PER_LIMIT, MAX_PEERS, PeerCounts, RateLimitStats,
};

#[test]
fn test_client_ip_window_unresolved_sums_every_reason() {
    let client_ip = ClientIpWindow {
        header_used: 100,
        peer_used: 100,
        unresolved_all_entries_trusted: 1,
        unresolved_header_missing: 2,
        unresolved_no_peer_info: 3,
        unresolved_unparseable_entry: 4,
        unresolved_untrusted_peer: 5,
        ..ClientIpWindow::default()
    };

    assert_eq!(client_ip.unresolved(), 15);
}

#[test]
fn test_rate_limit_stats_record_decision_caps_keys_per_limit() {
    // Setup statistics with a full key map for one limit
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    for index in 0..MAX_KEYS_PER_LIMIT {
        stats.record_decision(Limit::Views, limit_key(index), allowed(1));
    }

    // Record a new key, then a key that is already tracked
    stats.record_decision(Limit::Views, limit_key(MAX_KEYS_PER_LIMIT), denied());
    stats.record_decision(Limit::Views, limit_key(0), allowed(1));
    stats.record_decision(Limit::LogIn, limit_key(MAX_KEYS_PER_LIMIT), allowed(1));

    // Check the new key is counted only in the overflow bucket
    let window = stats.take_window(now);
    let views = window.limit(Limit::Views);
    assert_eq!(views.requests, MAX_KEYS_PER_LIMIT as u64 + 2);
    assert_eq!(views.over_limit, 1);
    assert_eq!(views.keys.entries.len(), MAX_KEYS_PER_LIMIT);
    assert!(views.keys.is_capped);
    assert_eq!(
        views.keys.other,
        KeyCounts {
            over_limit: 1,
            requests: 1
        }
    );
    assert!(!views.keys.entries.contains_key(&limit_key(MAX_KEYS_PER_LIMIT)));
    assert_eq!(views.keys.entries[&limit_key(0)].requests, 2);

    // Check the cap applies per limit
    let log_in = window.limit(Limit::LogIn);
    assert!(!log_in.keys.is_capped);
    assert_eq!(
        log_in.keys.entries[&limit_key(MAX_KEYS_PER_LIMIT)].requests,
        1
    );
}

#[test]
fn test_rate_limit_stats_record_decision_counts_store_outcomes() {
    // Setup statistics
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    let first = limit_key(1);
    let second = limit_key(2);

    // Record allowed, denied and untracked requests for one limit
    stats.record_decision(Limit::ExploreSearch, first, allowed(40));
    stats.record_decision(Limit::ExploreSearch, first, allowed(70));
    stats.record_decision(Limit::ExploreSearch, second, allowed(20));
    stats.record_decision(Limit::ExploreSearch, second, Decision::Untracked);

    // Check every request is counted and the peak follows allowed requests
    let window = stats.take_window(now);
    let explore = window.limit(Limit::ExploreSearch);
    assert_eq!(explore.requests, 4);
    assert_eq!(explore.over_limit, 0);
    assert_eq!(explore.peak_burst_used_pct, 70);
    assert_eq!(explore.untracked_store_full, 1);
    assert_eq!(
        explore.keys.entries[&first],
        KeyCounts {
            over_limit: 0,
            requests: 2
        }
    );
    assert_eq!(
        explore.keys.entries[&second],
        KeyCounts {
            over_limit: 0,
            requests: 2
        }
    );

    // Record a denied request
    stats.record_decision(Limit::ExploreSearch, first, allowed(10));
    stats.record_decision(Limit::ExploreSearch, first, denied());

    // Check a denial counts over the limit and marks the burst as fully used
    let window = stats.take_window(now);
    let explore = window.limit(Limit::ExploreSearch);
    assert_eq!(explore.requests, 2);
    assert_eq!(explore.over_limit, 1);
    assert_eq!(explore.peak_burst_used_pct, 100);
    assert_eq!(
        explore.keys.entries[&first],
        KeyCounts {
            over_limit: 1,
            requests: 2
        }
    );
    for limit in Limit::ALL.into_iter().filter(|l| *l != Limit::ExploreSearch) {
        assert!(!window.limit(limit).has_traffic(), "{}", limit.name());
    }
}

#[test]
fn test_rate_limit_stats_record_decision_tracks_user_keys() {
    // Setup statistics and two user keys
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    let first = LimitKey::User(Uuid::from_u128(1));
    let second = LimitKey::User(Uuid::from_u128(2));

    // Record allowed and denied requests for a user limit
    stats.record_decision(Limit::ImageUploads, first, allowed(50));
    stats.record_decision(Limit::ImageUploads, first, denied());
    stats.record_decision(Limit::ImageUploads, second, allowed(25));

    // Check the user keys are recorded without affecting client IP counters
    let window = stats.take_window(now);
    let uploads = window.limit(Limit::ImageUploads);
    assert_eq!(uploads.requests, 3);
    assert_eq!(uploads.over_limit, 1);
    assert_eq!(uploads.peak_burst_used_pct, 100);
    assert_eq!(
        uploads.keys.entries[&first],
        KeyCounts {
            over_limit: 1,
            requests: 2
        }
    );
    assert_eq!(
        uploads.keys.entries[&second],
        KeyCounts {
            over_limit: 0,
            requests: 1
        }
    );
    assert_eq!(window.client_ip, ClientIpWindow::default());
}

#[test]
fn test_rate_limit_stats_record_resolution_caps_internal_client_addresses() {
    // Setup statistics with a full internal client address map
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    for index in 0..MAX_INTERNAL_CLIENT_ADDRESSES {
        stats.record_resolution(None, false, &resolved_peer(key(index), true));
    }

    // Record a new internal address, a tracked one and an external one
    stats.record_resolution(
        None,
        false,
        &resolved_peer(key(MAX_INTERNAL_CLIENT_ADDRESSES), true),
    );
    stats.record_resolution(None, false, &resolved_peer(key(0), true));
    stats.record_resolution(None, false, &resolved_peer(key(100_000), false));

    // Check the new address is counted only in the overflow bucket
    let window = stats.take_window(now);
    let addresses = &window.client_ip.internal_client_addresses;
    assert_eq!(
        window.client_ip.internal_clients,
        MAX_INTERNAL_CLIENT_ADDRESSES as u64 + 2
    );
    assert_eq!(
        window.client_ip.peer_used,
        MAX_INTERNAL_CLIENT_ADDRESSES as u64 + 3
    );
    assert_eq!(addresses.entries.len(), MAX_INTERNAL_CLIENT_ADDRESSES);
    assert!(addresses.is_capped);
    assert_eq!(addresses.other, 1);
    assert_eq!(addresses.entries[&key(0)], 2);
    assert!(!addresses.entries.contains_key(&key(100_000)));
}

#[test]
fn test_rate_limit_stats_record_resolution_caps_peers() {
    // Setup statistics with a full peer map
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    let resolution = unresolved(None, UnresolvedReason::UntrustedPeer);
    for index in 0..MAX_PEERS {
        stats.record_resolution(Some(ip(index)), false, &resolution);
    }

    // Record a new peer, then a peer that is already tracked
    stats.record_resolution(Some(ip(MAX_PEERS)), true, &resolution);
    stats.record_resolution(Some(ip(0)), false, &resolution);

    // Check the new peer is counted only in the overflow bucket
    let window = stats.take_window(now);
    let peers = &window.proxy.peers;
    assert_eq!(peers.entries.len(), MAX_PEERS);
    assert!(peers.is_capped);
    assert_eq!(peers.other.requests, 1);
    assert_eq!(peers.entries[&ip(0)].requests, 2);
    assert!(!peers.entries.contains_key(&ip(MAX_PEERS)));
    assert_eq!(
        window.client_ip.unresolved_untrusted_peer,
        MAX_PEERS as u64 + 2
    );
}

#[test]
fn test_rate_limit_stats_record_resolution_counts_client_outcomes() {
    let internal_key = ClientKey::V4([10, 0, 0, 9]);
    let cases = [
        (
            "resolved from the peer",
            resolved_peer(key(1), false),
            ClientIpWindow {
                peer_used: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "resolved from the header",
            resolved_header(key(1), false, shape(1, false, 1)),
            ClientIpWindow {
                header_used: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "internal client",
            resolved_header(internal_key, true, shape(1, false, 1)),
            ClientIpWindow {
                header_used: 1,
                internal_client_addresses: CappedMap {
                    entries: HashMap::from([(internal_key, 1)]),
                    is_capped: false,
                    other: 0,
                },
                internal_clients: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "entries left of the client",
            resolved_header(key(1), false, shape(3, true, 1)),
            ClientIpWindow {
                entries_left_of_client: 1,
                header_used: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "all entries trusted",
            unresolved(
                Some(shape(2, false, 1)),
                UnresolvedReason::AllEntriesTrusted,
            ),
            ClientIpWindow {
                unresolved_all_entries_trusted: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "header missing",
            unresolved(None, UnresolvedReason::HeaderMissing),
            ClientIpWindow {
                unresolved_header_missing: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "no peer information",
            unresolved(None, UnresolvedReason::NoPeerInfo),
            ClientIpWindow {
                unresolved_no_peer_info: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "unparseable entry",
            unresolved(Some(shape(1, false, 1)), UnresolvedReason::UnparseableEntry),
            ClientIpWindow {
                unresolved_unparseable_entry: 1,
                ..ClientIpWindow::default()
            },
        ),
        (
            "untrusted peer",
            unresolved(None, UnresolvedReason::UntrustedPeer),
            ClientIpWindow {
                unresolved_untrusted_peer: 1,
                ..ClientIpWindow::default()
            },
        ),
    ];
    for (case, resolution, expected) in cases {
        // Record one resolution
        let now = Instant::now();
        let stats = RateLimitStats::new(now);
        stats.record_resolution(None, false, &resolution);

        // Check its client IP counters and that no limit counted it
        let window = stats.take_window(now);
        assert_eq!(window.client_ip, expected, "{case}");
        for limit in Limit::ALL {
            assert!(
                !window.limit(limit).has_traffic(),
                "{case}: {}",
                limit.name()
            );
        }
    }
}

#[test]
fn test_rate_limit_stats_record_resolution_records_header_shape() {
    // Setup statistics
    let now = Instant::now();
    let stats = RateLimitStats::new(now);

    // Record headers with several entry counts and line counts
    let shapes = [
        shape(0, false, 1),
        shape(1, false, 1),
        shape(1, false, 1),
        shape(2, true, 2),
        shape(MAX_CHAIN_LENGTH, false, 1),
        shape(MAX_CHAIN_LENGTH + 5, false, 3),
    ];
    for header in shapes {
        stats.record_resolution(None, false, &resolved_header(key(1), false, header));
    }
    stats.record_resolution(None, false, &resolved_peer(key(2), false));

    // Check the chain length distribution and the multiple line count
    let window = stats.take_window(now);
    let mut expected_chain_lengths = [0; MAX_CHAIN_LENGTH + 1];
    expected_chain_lengths[0] = 1;
    expected_chain_lengths[1] = 2;
    expected_chain_lengths[2] = 1;
    expected_chain_lengths[MAX_CHAIN_LENGTH] = 2;
    assert_eq!(window.proxy.chain_lengths, expected_chain_lengths);
    assert_eq!(window.proxy.multiple_header_lines, 2);
    assert_eq!(window.client_ip.entries_left_of_client, 1);
}

#[test]
fn test_rate_limit_stats_record_resolution_records_peer_trust() {
    // Setup statistics
    let now = Instant::now();
    let stats = RateLimitStats::new(now);
    let trusted_peer = IpAddr::V4(Ipv4Addr::new(10, 0, 0, 7));
    let mapped_trusted_peer: IpAddr = "::ffff:10.0.0.7".parse().unwrap();
    let client_peer = IpAddr::V4(Ipv4Addr::new(203, 0, 113, 7));

    // Record requests from a trusted peer, its IPv4-mapped form and a client peer
    let resolution = resolved_header(key(1), false, shape(1, false, 1));
    stats.record_resolution(Some(trusted_peer), true, &resolution);
    stats.record_resolution(Some(mapped_trusted_peer), true, &resolution);
    stats.record_resolution(Some(client_peer), false, &resolution);

    // Check each canonical peer is counted with its trust classification
    let window = stats.take_window(now);
    let peers = &window.proxy.peers;
    assert_eq!(peers.entries.len(), 2);
    assert!(!peers.is_capped);
    assert_eq!(
        peers.entries[&trusted_peer],
        PeerCounts {
            is_trusted_proxy: true,
            requests: 2
        }
    );
    assert_eq!(
        peers.entries[&client_peer],
        PeerCounts {
            is_trusted_proxy: false,
            requests: 1
        }
    );
}

#[test]
fn test_rate_limit_stats_record_skipped_origin_check_is_not_a_request() {
    // Setup statistics
    let now = Instant::now();
    let stats = RateLimitStats::new(now);

    // Record origin-check skips for one limit
    stats.record_skipped_origin_check(Limit::Views);
    stats.record_skipped_origin_check(Limit::Views);

    // Check the skips are counted apart from requests and give the limit traffic
    let window = stats.take_window(now);
    let views = window.limit(Limit::Views);
    assert_eq!(views.skipped_origin_check, 2);
    assert_eq!(views.requests, 0);
    assert!(views.keys.entries.is_empty());
    assert!(views.has_traffic());
    assert!(!window.is_empty());
}

#[test]
fn test_rate_limit_stats_take_window_swaps_window() {
    // Setup statistics with traffic in the first window
    let started = Instant::now();
    let stats = RateLimitStats::new(started);
    stats.record_resolution(None, false, &resolved_peer(key(1), false));
    stats.record_decision(Limit::SignUp, limit_key(1), allowed(1));

    // Take the first window
    let first_end = started + Duration::from_secs(300);
    let first = stats.take_window(first_end);

    // Check the first window holds the traffic and its duration
    assert_eq!(first.duration, Duration::from_secs(300));
    assert_eq!(first.client_ip.peer_used, 1);
    assert_eq!(first.limit(Limit::SignUp).requests, 1);
    assert!(!first.is_empty());

    // Take the next window
    let second = stats.take_window(first_end + Duration::from_secs(42));

    // Check the next window is empty and starts where the first ended
    assert_eq!(second.duration, Duration::from_secs(42));
    assert!(second.is_empty());
}

// Helpers.

/// Returns an allowed decision with the given burst usage.
fn allowed(used_pct: u8) -> Decision {
    Decision::Allowed { used_pct }
}

/// Returns a denied decision.
fn denied() -> Decision {
    Decision::Denied {
        retry_after: Duration::from_secs(1),
    }
}

/// Returns a distinct public IPv4 address for an index.
fn ip(index: usize) -> IpAddr {
    let [_, a, b, c] = u32::try_from(index).unwrap().to_be_bytes();
    IpAddr::V4(Ipv4Addr::new(198, a, b, c))
}

/// Returns a distinct IPv4 client key for an index.
fn key(index: usize) -> ClientKey {
    let [_, a, b, c] = u32::try_from(index).unwrap().to_be_bytes();
    ClientKey::V4([198, a, b, c])
}

/// Returns a distinct IP-backed limit key for an index.
fn limit_key(index: usize) -> LimitKey {
    LimitKey::Client(key(index))
}

/// Returns a resolution that selected the key from the header.
fn resolved_header(key: ClientKey, internal: bool, header: HeaderShape) -> Resolution {
    Resolution {
        outcome: Ok(ResolvedClient {
            internal,
            key,
            via: ResolvedVia::Header,
        }),
        header: Some(header),
    }
}

/// Returns a resolution that selected the key from the peer.
fn resolved_peer(key: ClientKey, internal: bool) -> Resolution {
    Resolution {
        outcome: Ok(ResolvedClient {
            internal,
            key,
            via: ResolvedVia::Peer,
        }),
        header: None,
    }
}

/// Returns a header shape.
fn shape(entries: usize, left_of_client: bool, lines: usize) -> HeaderShape {
    HeaderShape {
        entries,
        left_of_client,
        lines,
    }
}

/// Returns a resolution that selected no client.
fn unresolved(header: Option<HeaderShape>, reason: UnresolvedReason) -> Resolution {
    Resolution {
        outcome: Err(reason),
        header,
    }
}
