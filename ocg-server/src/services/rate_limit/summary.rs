//! Periodic summary of the rate limiting statistics.
//!
//! The `rate-limit-summary` worker takes the statistics window on a fixed
//! cadence, builds a [`SummaryReport`] from it with the pure
//! [`build_report`], and logs it through [`emit`], which only calls
//! `tracing`.

use std::{cmp::Reverse, collections::HashMap, fmt, sync::Arc, time::Duration};

use tokio::time::sleep;
use tokio_util::sync::CancellationToken;
use tracing::{Level, info, warn};

use crate::{
    config::RateLimitMode,
    services::workers::{BackgroundTasks, WorkerIteration, run_worker},
};

use super::{
    Limit, RateLimiter,
    client_ip::{is_internal, mask_ip},
    mode_name,
    stats::{ClientIpWindow, LimitWindow, MAX_CHAIN_LENGTH, ProxyWindow, WindowSnapshot},
};

#[cfg(test)]
mod tests;

/// Minimum number of requests a limit needs in a window before one key can
/// be reported as dominant.
const DOMINANT_KEY_MIN_REQUESTS: u64 = 100;

/// Share of a limit's requests, in permille, from which one key is dominant.
const DOMINANT_KEY_MIN_SHARE_PERMILLE: u64 = 500;

/// Share of header-resolved requests, in permille, that requests with entries
/// left of the client must exceed to trigger a warning.
const ENTRIES_LEFT_OF_CLIENT_SHARE_PERMILLE: u64 = 500;

/// Share of resolved requests, in permille, from which internal clients
/// trigger a warning.
const INTERNAL_CLIENTS_MIN_SHARE_PERMILLE: u64 = 50;

/// Permille in a whole.
const PERMILLE: u64 = 1_000;

/// Time covered by each summary window.
const SUMMARY_WINDOW: Duration = Duration::from_mins(5);

/// Number of internal client addresses listed in the internal clients warning.
const TOP_INTERNAL_CLIENT_ADDRESSES: usize = 5;

/// Number of client keys listed per limit.
const TOP_KEYS: usize = 5;

/// Number of peers listed in the proxy summary.
const TOP_PEERS: usize = 5;

/// Emits a tracing event at `warn` when `$level` is [`Level::WARN`], and at
/// `info` otherwise.
macro_rules! event_at {
    ($level:expr, $($arg:tt)+) => {
        if $level == Level::WARN {
            warn!($($arg)+);
        } else {
            info!($($arg)+);
        }
    };
}

/// Starts the rate limiting summary worker.
pub(super) fn start(rate_limiter: Arc<RateLimiter>, background_tasks: &BackgroundTasks) {
    let reporter = Reporter {
        cancellation_token: background_tasks.cancellation_token(),
        rate_limiter,
    };
    background_tasks.spawn("rate-limit-summary", async move {
        reporter.run().await;
    });
}

/// Reports the rate limiting statistics once per window.
struct Reporter {
    /// Coordinates graceful reporter shutdown.
    cancellation_token: CancellationToken,
    /// Limiter whose statistics are reported.
    rate_limiter: Arc<RateLimiter>,
}

impl Reporter {
    /// Reports every window until graceful shutdown, then reports the final
    /// window.
    async fn run(&self) {
        // Let the first window fill, reporting it early if shutdown comes first
        tokio::select! {
            biased;
            () = self.cancellation_token.cancelled() => {
                self.report();
                return;
            }
            () = sleep(SUMMARY_WINDOW) => {}
        }

        // Report each window as it ends
        run_worker(&self.cancellation_token, || async {
            self.report();
            WorkerIteration::Pause(SUMMARY_WINDOW)
        })
        .await;

        // Report the traffic recorded since the last report before stopping
        self.report();
    }

    /// Takes the current window and logs its report.
    fn report(&self) {
        let window = self.rate_limiter.take_window();
        let report = build_report(
            &window,
            self.rate_limiter.mode(),
            self.rate_limiter.source_name(),
        );
        emit(&report);
    }
}

/// Report of one statistics window.
#[derive(Clone, Debug, PartialEq)]
struct SummaryReport {
    /// Client IP resolution summary, present for every window.
    client_ip: ClientIpSummary,
    /// Summaries of the limits with traffic, in [`Limit`] order.
    limits: Vec<LimitSummary>,
    /// Warnings triggered by the window, each logged on its own line.
    warnings: Vec<SummaryWarning>,

    /// Peer and header shape summary, present when peers were seen.
    proxy: Option<ProxySummary>,
}

/// Client IP resolution counters of one window.
#[derive(Clone, Debug, PartialEq)]
struct ClientIpSummary {
    /// Resolved requests whose header has entries left of the selected client.
    entries_left_of_client: u64,
    /// Requests whose client was read from the header.
    header_used: u64,
    /// Resolved requests whose selected client is an internal address.
    internal_clients: u64,
    /// Level of the log line: `warn` when any request was unresolved.
    level: Level,
    /// Whether limits are applied or only observed.
    mode: RateLimitMode,
    /// Requests whose client is the TCP peer.
    peer_used: u64,
    /// Configured client IP source.
    source: &'static str,
    /// Requests unresolved because every header entry is trusted.
    unresolved_all_entries_trusted: u64,
    /// Requests unresolved because the header is absent or empty.
    unresolved_header_missing: u64,
    /// Requests unresolved because they carry no peer address.
    unresolved_no_peer_info: u64,
    /// Requests unresolved because the walk reached an unparseable entry.
    unresolved_unparseable_entry: u64,
    /// Requests unresolved because the peer is not a trusted proxy.
    unresolved_untrusted_peer: u64,
    /// Whole seconds covered by the window.
    window_secs: u64,
}

/// Peer and header shape summary of one window.
#[derive(Clone, Debug, PartialEq)]
struct ProxySummary {
    /// Requests per header entry count, empty buckets left out.
    chain_lengths: Vec<Counted>,
    /// Number of distinct peers tracked.
    distinct_peers: usize,
    /// Whether more distinct peers were seen than could be tracked.
    distinct_peers_capped: bool,
    /// Requests carrying more than one client IP header line.
    multiple_header_lines: u64,
    /// Most frequent peers, in full when trusted or internal and masked
    /// otherwise.
    top_peers: Vec<Counted>,
}

/// Summary of one limit during one window.
#[derive(Clone, Debug, PartialEq)]
struct LimitSummary {
    /// Number of distinct client keys tracked.
    distinct_keys: usize,
    /// Whether more distinct keys were seen than could be tracked.
    distinct_keys_capped: bool,
    /// Failed log-in store entries evicted to track new keys.
    evicted_store_full: u64,
    /// Level of the log line: `warn` when the store was full.
    level: Level,
    /// Limit summarised.
    limit: Limit,
    /// Whether limits are applied or only observed.
    mode: RateLimitMode,
    /// Requests over the limit, rejected or would-be rejected in observe mode.
    over_limit: u64,
    /// Number of tracked keys with at least one request over the limit.
    over_limit_keys: usize,
    /// Largest share of a key's burst in use, from 0 to 100.
    peak_burst_used_pct: u8,
    /// Store acquires for the limit, untracked ones included.
    requests: u64,
    /// Requests passed through uncounted because they failed the origin check.
    skipped_origin_check: u64,
    /// Most frequent tracked client keys, masked.
    top_keys: Vec<KeyShare>,
    /// Requests allowed untracked because the store is full.
    untracked_store_full: u64,
}

/// Warning triggered by one window.
#[derive(Clone, Debug, PartialEq)]
enum SummaryWarning {
    /// One key holds at least half of a limit's requests.
    DominantKey {
        /// Dominant key, masked, with its count and share.
        key: KeyShare,
        /// Limit the key dominates.
        limit: Limit,
    },
    /// Most header-resolved requests have entries left of the selected client.
    EntriesLeftOfClient {
        /// Resolved requests whose header has entries left of the client.
        entries_left_of_client: u64,
        /// Requests whose client was read from the header.
        header_used: u64,
    },
    /// A significant share of resolved requests selected internal clients.
    InternalClients {
        /// Most frequent internal addresses selected as clients, in full.
        internal_client_addresses: Vec<Counted>,
        /// Resolved requests whose selected client is an internal address.
        internal_clients: u64,
        /// Resolved requests.
        resolved_clients: u64,
    },
}

impl SummaryWarning {
    /// Returns the level the warning is logged at.
    fn level(&self) -> Level {
        match self {
            SummaryWarning::DominantKey { .. }
            | SummaryWarning::EntriesLeftOfClient { .. }
            | SummaryWarning::InternalClients { .. } => Level::WARN,
        }
    }
}

/// Label with its request count, logged as `label=requests`.
#[derive(Clone, Debug, PartialEq, Eq)]
struct Counted {
    /// Address or bucket the count belongs to.
    label: String,
    /// Requests counted for the label.
    requests: u64,
}

impl fmt::Display for Counted {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}={}", self.label, self.requests)
    }
}

/// Masked client key with its request count and share of the limit's
/// requests, logged as `key=requests(share%)`.
#[derive(Clone, Debug, PartialEq, Eq)]
struct KeyShare {
    /// Masked client key.
    key: String,
    /// Requests made by the key.
    requests: u64,
    /// Share of the limit's requests, in permille, never above 1000.
    share_permille: u64,
}

impl fmt::Display for KeyShare {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}={}({}.{}%)",
            self.key,
            self.requests,
            self.share_permille / 10,
            self.share_permille % 10
        )
    }
}

/// Builds the report of one statistics window.
fn build_report(
    window: &WindowSnapshot,
    mode: RateLimitMode,
    source: &'static str,
) -> SummaryReport {
    // Summarise client IP resolution, present for every window
    let client_ip = client_ip_summary(&window.client_ip, mode, source, window.duration);

    // Summarise peers and header shapes when peers were seen
    let proxy = (!window.proxy.peers.entries.is_empty()).then(|| proxy_summary(&window.proxy));

    // Summarise every limit with traffic
    let limits: Vec<LimitSummary> = Limit::ALL
        .into_iter()
        .filter(|limit| window.limit(*limit).has_traffic())
        .map(|limit| limit_summary(limit, window.limit(limit), mode))
        .collect();

    // Collect the client IP warnings, then the dominant key of each limit
    let mut warnings = Vec::new();
    warnings.extend(entries_left_of_client_warning(&window.client_ip));
    warnings.extend(internal_clients_warning(&window.client_ip));
    warnings.extend(limits.iter().filter_map(dominant_key_warning));

    SummaryReport {
        client_ip,
        limits,
        warnings,
        proxy,
    }
}

/// Builds the client IP summary of a window.
fn client_ip_summary(
    client_ip: &ClientIpWindow,
    mode: RateLimitMode,
    source: &'static str,
    duration: Duration,
) -> ClientIpSummary {
    ClientIpSummary {
        entries_left_of_client: client_ip.entries_left_of_client,
        header_used: client_ip.header_used,
        internal_clients: client_ip.internal_clients,
        level: if client_ip.unresolved() > 0 {
            Level::WARN
        } else {
            Level::INFO
        },
        mode,
        peer_used: client_ip.peer_used,
        source,
        unresolved_all_entries_trusted: client_ip.unresolved_all_entries_trusted,
        unresolved_header_missing: client_ip.unresolved_header_missing,
        unresolved_no_peer_info: client_ip.unresolved_no_peer_info,
        unresolved_unparseable_entry: client_ip.unresolved_unparseable_entry,
        unresolved_untrusted_peer: client_ip.unresolved_untrusted_peer,
        window_secs: duration.as_secs(),
    }
}

/// Returns the dominant key warning of a limit, if its top tracked key
/// holds at least half of its requests.
fn dominant_key_warning(limit: &LimitSummary) -> Option<SummaryWarning> {
    let top = limit.top_keys.first()?;
    let is_dominant = limit.requests >= DOMINANT_KEY_MIN_REQUESTS
        && reaches_share(
            top.requests,
            limit.requests,
            DOMINANT_KEY_MIN_SHARE_PERMILLE,
        );
    is_dominant.then(|| SummaryWarning::DominantKey {
        key: top.clone(),
        limit: limit.limit,
    })
}

/// Logs one report through `tracing`.
fn emit(report: &SummaryReport) {
    // Log the client IP summary
    let client_ip = &report.client_ip;
    event_at!(
        client_ip.level,
        mode = mode_name(client_ip.mode),
        source = client_ip.source,
        window_secs = client_ip.window_secs,
        peer_used = client_ip.peer_used,
        header_used = client_ip.header_used,
        unresolved_all_entries_trusted = client_ip.unresolved_all_entries_trusted,
        unresolved_header_missing = client_ip.unresolved_header_missing,
        unresolved_no_peer_info = client_ip.unresolved_no_peer_info,
        unresolved_unparseable_entry = client_ip.unresolved_unparseable_entry,
        unresolved_untrusted_peer = client_ip.unresolved_untrusted_peer,
        internal_clients = client_ip.internal_clients,
        entries_left_of_client = client_ip.entries_left_of_client,
        "rate limit client ip summary"
    );

    // Log the proxy summary
    if let Some(proxy) = &report.proxy {
        info!(
            distinct_peers = proxy.distinct_peers,
            distinct_peers_capped = proxy.distinct_peers_capped,
            top_peers = join(&proxy.top_peers),
            chain_lengths = join(&proxy.chain_lengths),
            multiple_header_lines = proxy.multiple_header_lines,
            "rate limit proxy summary"
        );
    }

    // Log one summary per limit with traffic
    for limit in &report.limits {
        event_at!(
            limit.level,
            limit = limit.limit.name(),
            mode = mode_name(limit.mode),
            requests = limit.requests,
            over_limit = limit.over_limit,
            over_limit_keys = limit.over_limit_keys,
            distinct_keys = limit.distinct_keys,
            distinct_keys_capped = limit.distinct_keys_capped,
            peak_burst_used_pct = limit.peak_burst_used_pct,
            untracked_store_full = limit.untracked_store_full,
            evicted_store_full = limit.evicted_store_full,
            skipped_origin_check = limit.skipped_origin_check,
            top_keys = join(&limit.top_keys),
            "rate limit summary"
        );
    }

    // Log each warning on its own line
    for warning in &report.warnings {
        match warning {
            SummaryWarning::DominantKey { key, limit } => event_at!(
                warning.level(),
                limit = limit.name(),
                key = %key,
                "rate limit dominant key; check the client ip configuration or shared nat"
            ),
            SummaryWarning::EntriesLeftOfClient {
                entries_left_of_client,
                header_used,
            } => event_at!(
                warning.level(),
                entries_left_of_client,
                header_used,
                "rate limit entries left of client; an unlisted proxy may be in front"
            ),
            SummaryWarning::InternalClients {
                internal_client_addresses,
                internal_clients,
                resolved_clients,
            } => event_at!(
                warning.level(),
                internal_clients,
                resolved_clients,
                internal_client_addresses = join(internal_client_addresses),
                "rate limit internal clients; check trusted_proxies"
            ),
        }
    }
}

/// Returns the entries left of client warning, if most header-resolved
/// requests have entries left of the selected client.
fn entries_left_of_client_warning(client_ip: &ClientIpWindow) -> Option<SummaryWarning> {
    let is_most = exceeds_share(
        client_ip.entries_left_of_client,
        client_ip.header_used,
        ENTRIES_LEFT_OF_CLIENT_SHARE_PERMILLE,
    );
    is_most.then_some(SummaryWarning::EntriesLeftOfClient {
        entries_left_of_client: client_ip.entries_left_of_client,
        header_used: client_ip.header_used,
    })
}

/// Returns whether `count` is strictly more than `permille` of a non-zero
/// `total`.
fn exceeds_share(count: u64, total: u64, permille: u64) -> bool {
    total > 0 && u128::from(count) * u128::from(PERMILLE) > u128::from(total) * u128::from(permille)
}

/// Returns the internal clients warning, if internal addresses were selected
/// for a significant share of resolved requests.
fn internal_clients_warning(client_ip: &ClientIpWindow) -> Option<SummaryWarning> {
    // Compare the internal clients with every resolved request
    let resolved_clients = client_ip.header_used + client_ip.peer_used;
    if !reaches_share(
        client_ip.internal_clients,
        resolved_clients,
        INTERNAL_CLIENTS_MIN_SHARE_PERMILLE,
    ) {
        return None;
    }

    // List the most frequent internal addresses in full: they are proxies, not clients
    let internal_client_addresses = top_entries(
        &client_ip.internal_client_addresses.entries,
        |requests| *requests,
        TOP_INTERNAL_CLIENT_ADDRESSES,
    )
    .into_iter()
    .map(|(key, requests)| Counted {
        label: key.to_string(),
        requests: *requests,
    })
    .collect();

    Some(SummaryWarning::InternalClients {
        internal_client_addresses,
        internal_clients: client_ip.internal_clients,
        resolved_clients,
    })
}

/// Joins items into one space-separated log field value.
fn join<T: fmt::Display>(items: &[T]) -> String {
    items.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
}

/// Builds the summary of one limit with traffic.
fn limit_summary(limit: Limit, window: &LimitWindow, mode: RateLimitMode) -> LimitSummary {
    // List the most frequent tracked keys, masked, with their share of every request
    let top_keys = top_entries(&window.keys.entries, |counts| counts.requests, TOP_KEYS)
        .into_iter()
        .map(|(key, counts)| KeyShare {
            key: key.masked(),
            requests: counts.requests,
            share_permille: share_permille(counts.requests, window.requests),
        })
        .collect();

    LimitSummary {
        distinct_keys: window.keys.entries.len(),
        distinct_keys_capped: window.keys.is_capped,
        evicted_store_full: window.evicted_store_full,
        level: if window.untracked_store_full > 0 || window.evicted_store_full > 0 {
            Level::WARN
        } else {
            Level::INFO
        },
        limit,
        mode,
        over_limit: window.over_limit,
        over_limit_keys: window
            .keys
            .entries
            .values()
            .filter(|counts| counts.over_limit > 0)
            .count(),
        peak_burst_used_pct: window.peak_burst_used_pct,
        requests: window.requests,
        skipped_origin_check: window.skipped_origin_check,
        top_keys,
        untracked_store_full: window.untracked_store_full,
    }
}

/// Builds the proxy summary of a window in which peers were seen.
fn proxy_summary(proxy: &ProxyWindow) -> ProxySummary {
    // Show trusted and internal peers in full; any other peer is a client and is masked
    let top_peers = top_entries(&proxy.peers.entries, |counts| counts.requests, TOP_PEERS)
        .into_iter()
        .map(|(peer, counts)| {
            let label = if counts.is_trusted_proxy || is_internal(peer) {
                peer.to_string()
            } else {
                mask_ip(peer)
            };
            Counted {
                label,
                requests: counts.requests,
            }
        })
        .collect();

    // List the non-empty header entry count buckets, the last one open-ended
    let chain_lengths = proxy
        .chain_lengths
        .iter()
        .enumerate()
        .filter(|(_, requests)| **requests > 0)
        .map(|(entries, requests)| Counted {
            label: if entries == MAX_CHAIN_LENGTH {
                format!("{entries}+")
            } else {
                entries.to_string()
            },
            requests: *requests,
        })
        .collect();

    ProxySummary {
        chain_lengths,
        distinct_peers: proxy.peers.entries.len(),
        distinct_peers_capped: proxy.peers.is_capped,
        multiple_header_lines: proxy.multiple_header_lines,
        top_peers,
    }
}

/// Returns whether `count` is at least `permille` of a non-zero `total`.
fn reaches_share(count: u64, total: u64, permille: u64) -> bool {
    total > 0
        && u128::from(count) * u128::from(PERMILLE) >= u128::from(total) * u128::from(permille)
}

/// Returns `count` as a share of `total` in permille, rounded down and never
/// above 1000.
fn share_permille(count: u64, total: u64) -> u64 {
    if total == 0 {
        return 0;
    }
    let permille = u128::from(count.min(total)) * u128::from(PERMILLE) / u128::from(total);
    u64::try_from(permille).unwrap_or(PERMILLE)
}

/// Returns the `count` entries with the most requests, most first, ties
/// broken by ascending key so the selection is deterministic.
fn top_entries<K: Copy + Ord, V>(
    entries: &HashMap<K, V>,
    requests: impl Fn(&V) -> u64,
    count: usize,
) -> Vec<(K, &V)> {
    let mut ranked: Vec<(K, &V)> = entries.iter().map(|(key, value)| (*key, value)).collect();
    ranked.sort_unstable_by_key(|(key, value)| (Reverse(requests(value)), *key));
    ranked.truncate(count);
    ranked
}
