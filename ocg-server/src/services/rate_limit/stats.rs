//! Bounded per-window statistics for the rate limiting summary.

use std::{
    collections::HashMap,
    hash::Hash,
    mem,
    net::IpAddr,
    sync::{Mutex, MutexGuard, PoisonError},
    time::{Duration, Instant},
};

use uuid::Uuid;

use super::{
    Limit,
    client_ip::{ClientKey, Resolution, ResolvedVia, UnresolvedReason},
    store::Decision,
};

#[cfg(test)]
mod tests;

/// Largest header entry count with its own `chain_lengths` bucket; longer
/// chains share the last bucket.
pub(super) const MAX_CHAIN_LENGTH: usize = 8;

/// Maximum number of distinct internal client addresses tracked per window.
const MAX_INTERNAL_CLIENT_ADDRESSES: usize = 256;

/// Maximum number of distinct keys tracked per limit per window.
const MAX_KEYS_PER_LIMIT: usize = 4_096;

/// Maximum number of distinct peers tracked per window.
const MAX_PEERS: usize = 256;

/// Statistics of the current window, shared by every request.
///
/// Every structure is bounded, so memory stays bounded even if the window is
/// never taken. Each record holds the lock for one short synchronous update
/// and is never made while a store lock is held.
pub(super) struct RateLimitStats {
    /// Window being recorded.
    window: Mutex<Window>,
}

impl RateLimitStats {
    /// Creates statistics whose first window starts at `now`.
    pub(super) fn new(now: Instant) -> Self {
        Self {
            window: Mutex::new(Window::new(now)),
        }
    }

    /// Records the outcome of one store acquire for a limit.
    ///
    /// For the failed log-in limit, `key` carries the client IP key alone, so
    /// no username or username hash is ever kept in statistics.
    pub(super) fn record_decision(&self, limit: Limit, key: LimitKey, decision: Decision) {
        let mut window = self.window();
        let limit_window = window.snapshot.limit_mut(limit);

        // Count the request for the limit and its key
        limit_window.requests += 1;
        let key_counts = limit_window.keys.slot(key, MAX_KEYS_PER_LIMIT);
        key_counts.requests += 1;

        // Count the store outcome
        match decision {
            Decision::Allowed { used_pct } => {
                limit_window.peak_burst_used_pct = limit_window.peak_burst_used_pct.max(used_pct);
            }
            Decision::Denied { .. } => {
                key_counts.over_limit += 1;
                limit_window.over_limit += 1;
                limit_window.peak_burst_used_pct = 100;
            }
            Decision::Untracked => limit_window.untracked_store_full += 1,
        }
    }

    /// Records the client IP and proxy data of one resolution.
    ///
    /// `is_trusted_peer` is recorded with the peer so the summary can decide
    /// how to display it without the resolver.
    pub(super) fn record_resolution(
        &self,
        peer: Option<IpAddr>,
        is_trusted_peer: bool,
        resolution: &Resolution,
    ) {
        let mut window = self.window();
        let snapshot = &mut window.snapshot;

        // Count the peer the request came from
        if let Some(peer) = peer {
            let peer_counts = snapshot.proxy.peers.slot(peer.to_canonical(), MAX_PEERS);
            peer_counts.is_trusted_proxy = is_trusted_peer;
            peer_counts.requests += 1;
        }

        // Record the shape of the client IP header
        if let Some(header) = resolution.header {
            snapshot.proxy.chain_lengths[header.entries.min(MAX_CHAIN_LENGTH)] += 1;
            if header.lines > 1 {
                snapshot.proxy.multiple_header_lines += 1;
            }
            if header.left_of_client {
                snapshot.client_ip.entries_left_of_client += 1;
            }
        }

        // Count the resolved client, or the reason no client was selected
        let client_ip = &mut snapshot.client_ip;
        match resolution.outcome {
            Ok(client) => {
                match client.via {
                    ResolvedVia::Header => client_ip.header_used += 1,
                    ResolvedVia::Peer => client_ip.peer_used += 1,
                }
                if client.internal {
                    client_ip.internal_clients += 1;
                    *client_ip
                        .internal_client_addresses
                        .slot(client.key, MAX_INTERNAL_CLIENT_ADDRESSES) += 1;
                }
            }
            Err(UnresolvedReason::AllEntriesTrusted) => {
                client_ip.unresolved_all_entries_trusted += 1;
            }
            Err(UnresolvedReason::HeaderMissing) => client_ip.unresolved_header_missing += 1,
            Err(UnresolvedReason::NoPeerInfo) => client_ip.unresolved_no_peer_info += 1,
            Err(UnresolvedReason::UnparseableEntry) => {
                client_ip.unresolved_unparseable_entry += 1;
            }
            Err(UnresolvedReason::UntrustedPeer) => client_ip.unresolved_untrusted_peer += 1,
        }
    }

    /// Records a request to a limit skipped because it failed the origin check.
    pub(super) fn record_skipped_origin_check(&self, limit: Limit) {
        self.window().snapshot.limit_mut(limit).skipped_origin_check += 1;
    }

    /// Swaps the current window out at `now` and starts an empty one.
    pub(super) fn take_window(&self, now: Instant) -> WindowSnapshot {
        let window = mem::replace(&mut *self.window(), Window::new(now));
        let mut snapshot = window.snapshot;
        snapshot.duration = now.saturating_duration_since(window.started);
        snapshot
    }

    /// Locks the current window, recovering the lock if it was poisoned.
    ///
    /// Recovery is safe because every update only increments counters, so a
    /// panic can at worst lose part of one request's statistics.
    fn window(&self) -> MutexGuard<'_, Window> {
        self.window.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Window being recorded and the time it started.
struct Window {
    /// Statistics recorded so far.
    snapshot: WindowSnapshot,
    /// Time the window started.
    started: Instant,
}

impl Window {
    /// Creates an empty window starting at `now`.
    fn new(now: Instant) -> Self {
        Self {
            snapshot: WindowSnapshot::default(),
            started: now,
        }
    }
}

/// Statistics recorded during one window.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct WindowSnapshot {
    /// Client IP resolution counters.
    pub client_ip: ClientIpWindow,
    /// Time covered by the window.
    pub duration: Duration,
    /// Per limit statistics, indexed by [`Limit`].
    limits: [LimitWindow; Limit::ALL.len()],
    /// Peer and header shape data.
    pub proxy: ProxyWindow,
}

impl WindowSnapshot {
    /// Returns whether nothing was recorded during the window.
    #[cfg(test)]
    pub(crate) fn is_empty(&self) -> bool {
        self.client_ip == ClientIpWindow::default()
            && self.proxy == ProxyWindow::default()
            && self.limits.iter().all(|limit| *limit == LimitWindow::default())
    }

    /// Returns the statistics of one limit.
    pub(crate) fn limit(&self, limit: Limit) -> &LimitWindow {
        &self.limits[limit as usize]
    }

    /// Returns the statistics of one limit for updating.
    pub(super) fn limit_mut(&mut self, limit: Limit) -> &mut LimitWindow {
        &mut self.limits[limit as usize]
    }
}

/// Client IP resolution counters of one window.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ClientIpWindow {
    /// Resolved requests whose header has entries left of the selected client.
    pub entries_left_of_client: u64,
    /// Requests whose client was read from the header.
    pub header_used: u64,
    /// Internal addresses selected as clients, with their request counts.
    pub internal_client_addresses: CappedMap<ClientKey, u64>,
    /// Resolved requests whose selected client is an internal address.
    pub internal_clients: u64,
    /// Requests whose client is the TCP peer.
    pub peer_used: u64,
    /// Requests unresolved because every header entry is trusted.
    pub unresolved_all_entries_trusted: u64,
    /// Requests unresolved because the header is absent or empty.
    pub unresolved_header_missing: u64,
    /// Requests unresolved because they carry no peer address.
    pub unresolved_no_peer_info: u64,
    /// Requests unresolved because the walk reached an unparseable entry.
    pub unresolved_unparseable_entry: u64,
    /// Requests unresolved because the peer is not a trusted proxy.
    pub unresolved_untrusted_peer: u64,
}

impl ClientIpWindow {
    /// Returns the number of unresolved requests across every reason.
    pub(crate) fn unresolved(&self) -> u64 {
        self.unresolved_all_entries_trusted
            + self.unresolved_header_missing
            + self.unresolved_no_peer_info
            + self.unresolved_unparseable_entry
            + self.unresolved_untrusted_peer
    }
}

/// Key tracked in per-limit statistics: a client address key or an
/// authenticated user identifier.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub(crate) enum LimitKey {
    /// Client IP address or IPv6 /64 prefix.
    Client(ClientKey),
    /// Authenticated user identifier.
    User(Uuid),
}

/// Statistics of one limit during one window.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct LimitWindow {
    /// Store entries evicted to track new keys.
    pub evicted_store_full: u64,
    /// Request counts per limit key.
    pub keys: CappedMap<LimitKey, KeyCounts>,
    /// Requests over the limit, rejected or would-be rejected in observe mode.
    pub over_limit: u64,
    /// Largest share of a key's burst in use, from 0 to 100.
    pub peak_burst_used_pct: u8,
    /// Store acquires for the limit, untracked ones included.
    pub requests: u64,
    /// Requests passed through uncounted because they failed the origin check.
    pub skipped_origin_check: u64,
    /// Requests allowed untracked because the store is full.
    pub untracked_store_full: u64,
}

impl LimitWindow {
    /// Returns whether the limit saw any request during the window.
    pub(crate) fn has_traffic(&self) -> bool {
        self.requests + self.skipped_origin_check > 0
    }
}

/// Request counts of one limit key for one limit.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct KeyCounts {
    /// Requests over the limit.
    pub over_limit: u64,
    /// Store acquires.
    pub requests: u64,
}

/// Peer and header shape data of one window.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ProxyWindow {
    /// Requests per header entry count; the last bucket holds
    /// [`MAX_CHAIN_LENGTH`] entries or more.
    pub chain_lengths: [u64; MAX_CHAIN_LENGTH + 1],
    /// Requests carrying more than one client IP header line.
    pub multiple_header_lines: u64,
    /// Request counts per canonical peer address; the trust flag of the
    /// overflow bucket carries no meaning.
    pub peers: CappedMap<IpAddr, PeerCounts>,
}

/// Request counts of one peer.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct PeerCounts {
    /// Whether the peer is inside a trusted proxy network.
    pub is_trusted_proxy: bool,
    /// Requests received from the peer.
    pub requests: u64,
}

/// Map with a bounded number of keys and an overflow bucket.
///
/// Once the map holds its maximum number of keys, values for new keys are
/// accumulated in `other` and `is_capped` is set; keys already tracked keep
/// their own values.
#[derive(Clone, Debug)]
pub(crate) struct CappedMap<K, V> {
    /// Values of the tracked keys.
    pub entries: HashMap<K, V>,
    /// Whether a new key was counted in the overflow bucket.
    pub is_capped: bool,
    /// Accumulated values of the keys that did not fit.
    pub other: V,
}

impl<K: Eq + Hash, V: Default> CappedMap<K, V> {
    /// Returns the value of `key`, or the overflow bucket when the map is full.
    fn slot(&mut self, key: K, capacity: usize) -> &mut V {
        if self.entries.len() < capacity || self.entries.contains_key(&key) {
            return self.entries.entry(key).or_default();
        }
        self.is_capped = true;
        &mut self.other
    }
}

impl<K, V: Default> Default for CappedMap<K, V> {
    fn default() -> Self {
        Self {
            entries: HashMap::new(),
            is_capped: false,
            other: V::default(),
        }
    }
}

impl<K: Eq + Hash, V: PartialEq> PartialEq for CappedMap<K, V> {
    fn eq(&self, other: &Self) -> bool {
        self.entries == other.entries
            && self.is_capped == other.is_capped
            && self.other == other.other
    }
}
