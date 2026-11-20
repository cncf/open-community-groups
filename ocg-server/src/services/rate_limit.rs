//! Opt-in, per-pod, in-memory rate limiting for unauthenticated routes.

use std::{
    fmt,
    hash::{BuildHasher, RandomState},
    net::IpAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use anyhow::Result;
use axum::http::HeaderMap;
use tracing::info;

use crate::{
    config::{RateLimitBudget, RateLimitBudgets, RateLimitConfig, RateLimitMode},
    services::workers::BackgroundTasks,
};

use self::{
    client_ip::{ClientIpResolver, ClientKey},
    stats::{RateLimitStats, WindowSnapshot},
    store::{Decision, KeyedLimiter, OnFull, nanos_since},
};

pub(crate) mod client_ip;
mod stats;
mod store;
mod summary;
#[cfg(test)]
mod tests;

/// Byte that stands for each run of non-ASCII characters in a folded username.
const NON_ASCII_PLACEHOLDER: u8 = 0xFF;

/// Per-pod limiter for every rate limit, with its statistics.
///
/// Observe mode runs the same store operations and records the same
/// statistics as enforce mode; it only never rejects.
pub(crate) struct RateLimiter {
    /// Effective budget of every limit.
    budgets: RateLimitBudgets,
    /// Process epoch the stores measure time from.
    epoch: Instant,
    /// IP-keyed stores, indexed by [`IpLimit`].
    ip_stores: [KeyedLimiter<ClientKey>; IpLimit::ALL.len()],
    /// Failed log-in store keyed by client and folded username hash.
    log_in_failures_store: KeyedLimiter<LogInFailureKey>,
    /// Whether limits are applied or only observed.
    mode: RateLimitMode,
    /// Client IP resolver built from the configuration.
    resolver: ClientIpResolver,
    /// Statistics of the current window.
    stats: RateLimitStats,
    /// Process-random hasher for folded usernames, so collisions cannot be
    /// precomputed.
    username_hasher: RandomState,
}

impl RateLimiter {
    /// Builds a limiter from the validated configuration, with `now` as the
    /// process epoch and the start of the first statistics window.
    pub(crate) fn new(cfg: &RateLimitConfig, now: Instant) -> Result<Self> {
        // Build the client IP resolver
        let resolver = ClientIpResolver::new(&cfg.client_ip)?;

        // Build one store per limit with its effective budget and full-store policy
        let ip_stores = IpLimit::ALL.map(|limit| {
            let budget = Limit::from(limit).budget(&cfg.limits);
            KeyedLimiter::new(budget, OnFull::AllowUntracked)
        });
        let log_in_failures_store = KeyedLimiter::new(
            Limit::LogInFailures.budget(&cfg.limits),
            OnFull::EvictLeastPenalised,
        );

        Ok(Self {
            budgets: cfg.limits.clone(),
            epoch: now,
            ip_stores,
            log_in_failures_store,
            mode: cfg.mode,
            resolver,
            stats: RateLimitStats::new(now),
            username_hasher: RandomState::new(),
        })
    }

    /// Returns the effective budget of every limit.
    pub(crate) fn budgets(&self) -> &RateLimitBudgets {
        &self.budgets
    }

    /// Applies one request from `client` to an IP-keyed limit.
    ///
    /// The request is always counted. Only enforce mode rejects a request
    /// over the limit; observe mode lets it through and reports that enforce
    /// mode would have rejected it.
    pub(crate) fn check(&self, limit: IpLimit, client: ClientKey, now: Instant) -> Verdict {
        // Apply the request to the limit's store and record the outcome
        let decision = self.ip_stores[limit as usize].acquire(client, nanos_since(self.epoch, now));
        self.stats.record_decision(Limit::from(limit), client, decision);

        // Reject only in enforce mode
        match (decision, self.mode) {
            (Decision::Denied { retry_after }, RateLimitMode::Enforce) => {
                Verdict::Reject { retry_after }
            }
            (Decision::Denied { .. }, RateLimitMode::Observe) => Verdict::AllowOverLimit,
            _ => Verdict::Allow,
        }
    }

    /// Returns the failed log-in limit of one client.
    pub(crate) fn log_in_failure_limit(self: &Arc<Self>, client: ClientKey) -> LogInFailureLimit {
        LogInFailureLimit {
            client,
            rate_limiter: Arc::clone(self),
        }
    }

    /// Returns whether limits are applied or only observed.
    pub(crate) fn mode(&self) -> RateLimitMode {
        self.mode
    }

    /// Records a request to a limit passed through uncounted because it is
    /// cross-origin.
    pub(crate) fn record_skipped_cross_origin(&self, limit: IpLimit) {
        self.stats.record_skipped_cross_origin(Limit::from(limit));
    }

    /// Resolves the client of a request and records the client IP and proxy
    /// statistics.
    ///
    /// Returns `None` for an unresolved client, which is never limited.
    pub(crate) fn resolve_client(
        &self,
        peer: Option<IpAddr>,
        headers: &HeaderMap,
    ) -> Option<ClientKey> {
        // Resolve the client and record its statistics with the peer's trust
        let resolution = self.resolver.resolve(peer, headers);
        let is_trusted_peer = peer.is_some_and(|peer| self.resolver.is_trusted_proxy(peer));
        self.stats.record_resolution(peer, is_trusted_peer, &resolution);

        resolution.outcome.ok().map(|client| client.key)
    }

    /// Returns the configured client IP source as its `snake_case` config value.
    pub(crate) fn source_name(&self) -> &'static str {
        self.resolver.source_name()
    }

    /// Swaps the current statistics window out and starts an empty one.
    pub(crate) fn take_window(&self) -> WindowSnapshot {
        // Take the recorded window
        let mut snapshot = self.stats.take_window(Instant::now());

        // Add the evictions the failed log-in store made since the last take
        snapshot.limit_mut(Limit::LogInFailures).evicted_store_full +=
            self.log_in_failures_store.take_evictions();

        snapshot
    }

    /// Returns the number of configured trusted proxy networks.
    pub(crate) fn trusted_proxy_count(&self) -> usize {
        self.resolver.trusted_proxy_count()
    }

    /// Returns the process-random hash of a folded username.
    fn username_hash(&self, username: &str) -> u64 {
        self.username_hasher.hash_one(fold_username(username))
    }
}

/// Limit applied per client address by the router middleware.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub(crate) enum IpLimit {
    /// Badge verification.
    BadgeVerify,
    /// Explore searches.
    ExploreSearch,
    /// External authentication redirects and callbacks.
    ExternalAuth,
    /// Log-in attempts.
    LogIn,
    /// Sign-ups.
    SignUp,
    /// Email verification links.
    VerifyEmail,
    /// Page view beacons.
    Views,
}

impl IpLimit {
    /// Every IP limit, in declaration order.
    pub(crate) const ALL: [IpLimit; 7] = [
        IpLimit::BadgeVerify,
        IpLimit::ExploreSearch,
        IpLimit::ExternalAuth,
        IpLimit::LogIn,
        IpLimit::SignUp,
        IpLimit::VerifyEmail,
        IpLimit::Views,
    ];
}

/// Identifies a limit in budgets, statistics and log lines.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub(crate) enum Limit {
    /// Badge verification.
    BadgeVerify,
    /// Explore searches.
    ExploreSearch,
    /// External authentication redirects and callbacks.
    ExternalAuth,
    /// Log-in attempts.
    LogIn,
    /// Failed log-ins per client and username.
    LogInFailures,
    /// Sign-ups.
    SignUp,
    /// Email verification links.
    VerifyEmail,
    /// Page view beacons.
    Views,
}

impl Limit {
    /// Every limit, in declaration order.
    pub(crate) const ALL: [Limit; 8] = [
        Limit::BadgeVerify,
        Limit::ExploreSearch,
        Limit::ExternalAuth,
        Limit::LogIn,
        Limit::LogInFailures,
        Limit::SignUp,
        Limit::VerifyEmail,
        Limit::Views,
    ];

    /// Returns the limit's `snake_case` configuration key.
    pub(crate) fn name(self) -> &'static str {
        match self {
            Limit::BadgeVerify => "badge_verify",
            Limit::ExploreSearch => "explore_search",
            Limit::ExternalAuth => "external_auth",
            Limit::LogIn => "log_in",
            Limit::LogInFailures => "log_in_failures",
            Limit::SignUp => "sign_up",
            Limit::VerifyEmail => "verify_email",
            Limit::Views => "views",
        }
    }

    /// Returns the limit's budget from the effective budgets.
    fn budget(self, budgets: &RateLimitBudgets) -> RateLimitBudget {
        match self {
            Limit::BadgeVerify => budgets.badge_verify,
            Limit::ExploreSearch => budgets.explore_search,
            Limit::ExternalAuth => budgets.external_auth,
            Limit::LogIn => budgets.log_in,
            Limit::LogInFailures => budgets.log_in_failures,
            Limit::SignUp => budgets.sign_up,
            Limit::VerifyEmail => budgets.verify_email,
            Limit::Views => budgets.views,
        }
    }
}

impl From<IpLimit> for Limit {
    fn from(limit: IpLimit) -> Self {
        match limit {
            IpLimit::BadgeVerify => Limit::BadgeVerify,
            IpLimit::ExploreSearch => Limit::ExploreSearch,
            IpLimit::ExternalAuth => Limit::ExternalAuth,
            IpLimit::LogIn => Limit::LogIn,
            IpLimit::SignUp => Limit::SignUp,
            IpLimit::VerifyEmail => Limit::VerifyEmail,
            IpLimit::Views => Limit::Views,
        }
    }
}

/// Result of checking an IP limit.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Verdict {
    /// Let the request through.
    Allow,
    /// Let the request through in observe mode, although it is over the
    /// limit and enforce mode would reject it.
    AllowOverLimit,
    /// Reject the request.
    Reject {
        /// Time until the client's next request would be allowed.
        retry_after: Duration,
    },
}

/// Refusal of a failed log-in reservation in enforce mode.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct RateLimited {
    /// Time until the next attempt would be allowed.
    pub retry_after: Duration,
}

/// Failed log-in limit of one client, inserted as a request extension.
#[derive(Clone)]
pub(crate) struct LogInFailureLimit {
    /// Key of the client making the request.
    client: ClientKey,
    /// Limiter holding the failed log-in store.
    rate_limiter: Arc<RateLimiter>,
}

impl LogInFailureLimit {
    /// Reserves one failed attempt for the client and username at `now`.
    ///
    /// The attempt is counted whatever the outcome. In enforce mode a denied
    /// reservation is refused; in observe mode it becomes a reservation that
    /// holds no token.
    pub(crate) fn reserve(
        &self,
        username: &str,
        now: Instant,
    ) -> Result<LogInFailureReservation, RateLimited> {
        let rate_limiter = &self.rate_limiter;

        // Acquire a token for the client and folded username, and record the outcome
        let key = LogInFailureKey {
            client: self.client,
            username_hash: rate_limiter.username_hash(username),
        };
        let decision = rate_limiter
            .log_in_failures_store
            .acquire(key, nanos_since(rate_limiter.epoch, now));
        rate_limiter
            .stats
            .record_decision(Limit::LogInFailures, self.client, decision);

        // Refuse a denied reservation only in enforce mode
        let holds_token = match (decision, rate_limiter.mode) {
            (Decision::Allowed { .. }, _) => true,
            (Decision::Denied { retry_after }, RateLimitMode::Enforce) => {
                return Err(RateLimited { retry_after });
            }
            (Decision::Denied { .. } | Decision::Untracked, _) => false,
        };

        Ok(LogInFailureReservation {
            holds_token,
            key,
            rate_limiter: Arc::clone(rate_limiter),
        })
    }
}

impl fmt::Debug for LogInFailureLimit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LogInFailureLimit")
            .field("client", &self.client)
            .finish_non_exhaustive()
    }
}

/// Failed log-in attempt reserved before authenticating.
///
/// Dropping the reservation refunds its token, so only attempts confirmed
/// with [`LogInFailureReservation::record_failure`] count against the budget.
pub(crate) struct LogInFailureReservation {
    /// Whether the acquire took a token that a drop must refund.
    holds_token: bool,
    /// Key the token was taken from.
    key: LogInFailureKey,
    /// Limiter holding the failed log-in store.
    rate_limiter: Arc<RateLimiter>,
}

impl LogInFailureReservation {
    /// Confirms the failed attempt, keeping its token.
    ///
    /// A no-op for a reservation that holds no token.
    pub(crate) fn record_failure(mut self) {
        self.holds_token = false;
    }
}

impl fmt::Debug for LogInFailureReservation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LogInFailureReservation")
            .field("holds_token", &self.holds_token)
            .finish_non_exhaustive()
    }
}

impl Drop for LogInFailureReservation {
    /// Refunds the token of an attempt that was not confirmed as a failure.
    fn drop(&mut self) {
        if self.holds_token {
            self.rate_limiter.log_in_failures_store.refund(&self.key);
        }
    }
}

/// Key of the failed log-in store.
///
/// The username is kept only as a process-random hash of its folded form.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
struct LogInFailureKey {
    /// Key of the client making the attempt.
    client: ClientKey,
    /// Hash of the folded username.
    username_hash: u64,
}

/// Returns every limit with its effective budget, for the startup log.
pub(crate) fn budget_lines(budgets: &RateLimitBudgets) -> [(Limit, RateLimitBudget); 8] {
    Limit::ALL.map(|limit| (limit, limit.budget(budgets)))
}

/// Builds the rate limiter from its configuration and starts its summary
/// worker.
///
/// Returns `None`, starting nothing, when rate limiting is not configured.
pub(crate) fn setup(
    cfg: Option<&RateLimitConfig>,
    background_tasks: &BackgroundTasks,
) -> Result<Option<Arc<RateLimiter>>> {
    let Some(cfg) = cfg else {
        return Ok(None);
    };

    // Build the limiter, with the process start as its epoch
    let rate_limiter = Arc::new(RateLimiter::new(cfg, Instant::now())?);

    // Log the configuration and every effective budget
    info!(
        mode = mode_name(rate_limiter.mode()),
        source = rate_limiter.source_name(),
        trusted_proxies = rate_limiter.trusted_proxy_count(),
        "rate limiting enabled"
    );
    for (limit, budget) in budget_lines(rate_limiter.budgets()) {
        info!(
            limit = limit.name(),
            burst = budget.burst,
            period_secs = budget.period_secs,
            "rate limit budget"
        );
    }

    // Start the periodic summary
    summary::start(Arc::clone(&rate_limiter), background_tasks);

    Ok(Some(rate_limiter))
}

/// Folds a username so every spelling that reaches the same account gets the
/// same failed log-in key.
///
/// The username is trimmed, U+212A KELVIN SIGN becomes `k` and U+0130 LATIN
/// CAPITAL LETTER I WITH DOT ABOVE becomes `i` (the non-ASCII characters the
/// database's `lower()` maps to ASCII), ASCII letters are lowercased, and
/// each run of remaining non-ASCII characters becomes one placeholder.
/// U+0131 LATIN SMALL LETTER DOTLESS I also becomes `i` and U+0307 COMBINING
/// DOT ABOVE is dropped, because ICU and Turkish or Azeri collations lower
/// U+0130 to `i` followed by U+0307 and `I` to U+0131. The merge is
/// deliberately conservative: distinct accounts may share a key, but one
/// account never gets two.
fn fold_username(username: &str) -> Vec<u8> {
    let mut folded = Vec::with_capacity(username.len());
    for ch in username.trim().chars() {
        // Drop the combining dot above, which some collations add to `i`
        if ch == '\u{0307}' {
            continue;
        }

        // Map each character to its folded byte
        let byte = match ch {
            '\u{212A}' => b'k',
            '\u{0130}' | '\u{0131}' => b'i',
            ch if ch.is_ascii() => {
                u8::try_from(ch.to_ascii_lowercase()).unwrap_or(NON_ASCII_PLACEHOLDER)
            }
            _ => NON_ASCII_PLACEHOLDER,
        };

        // Merge consecutive non-ASCII characters into one placeholder
        if byte == NON_ASCII_PLACEHOLDER && folded.last() == Some(&NON_ASCII_PLACEHOLDER) {
            continue;
        }
        folded.push(byte);
    }
    folded
}

/// Returns the mode as its `snake_case` configuration value, for log lines.
fn mode_name(mode: RateLimitMode) -> &'static str {
    match mode {
        RateLimitMode::Enforce => "enforce",
        RateLimitMode::Observe => "observe",
    }
}
