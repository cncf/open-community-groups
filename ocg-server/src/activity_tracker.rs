//! This module contains types and functionality used to track activities.
//!
//! It provides an asynchronous, batched mechanism for aggregating and
//! persisting tracked activities to the database. Tracking is deliberately
//! lossy: a request never waits for the tracker, and activities that cannot be
//! queued or aggregated within the configured bounds are dropped and counted.

use std::{
    collections::{HashMap, hash_map::Entry},
    hash::Hash,
    sync::{
        Arc, LazyLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use time::{
    OffsetDateTime,
    format_description::{self, FormatItem},
};
use tokio::{
    sync::mpsc::{self, error::TrySendError},
    time::{Instant, MissedTickBehavior},
};
use tokio_util::sync::CancellationToken;
use tracing::{error, warn};
use uuid::Uuid;

use crate::{
    db::activity_tracker::DynDBActivityTracker, services::workers::BackgroundTasks,
    types::utm::UtmParams,
};

#[cfg(test)]
mod tests;

/// Format used to represent the date in the tracker.
static DATE_FORMAT: LazyLock<Vec<FormatItem<'static>>> = LazyLock::new(|| {
    format_description::parse_borrowed::<1>("[year]-[month]-[day]").expect("format to be valid")
});

/// Capacity of the queue between request handlers and the aggregator.
///
/// Activities are tiny, so a large queue absorbs traffic bursts and short
/// aggregator stalls at negligible memory cost.
const ACTIVITIES_QUEUE_CAPACITY: usize = 10_000;

/// Capacity of the queue between the aggregator and the flusher.
///
/// A single slot is enough: when the flusher is still busy at the next flush,
/// the aggregator keeps merging activities into its current batch instead of
/// waiting for a free slot.
const BATCHES_QUEUE_CAPACITY: usize = 1;

/// How often activities will be written to the database.
#[cfg(not(test))]
const FLUSH_FREQUENCY: Duration = Duration::from_mins(5);
#[cfg(test)]
const FLUSH_FREQUENCY: Duration = Duration::from_millis(100);

/// Maximum distinct (entity, day) keys aggregated in one batch across all activities.
const MAX_BATCH_KEYS: usize = 10_000;

/// Maximum distinct (entity, day, UTM parameters) keys aggregated in one batch.
///
/// UTM keys have their own budget, so arbitrary UTM values cannot displace
/// the view counters.
const MAX_BATCH_UTM_KEYS: usize = 10_000;

/// Entity identifier tracked by the activity tracker.
type EntityId = Uuid;

/// Date string in `YYYY-MM-DD` format.
type Day = String;

/// Aggregated count for a day.
type Total = u32;

/// Trackable activities currently supported by the tracker.
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(clippy::enum_variant_names)]
pub(crate) enum Activity {
    /// A single community view.
    CommunityView {
        /// Viewed community.
        community_id: Uuid,
    },
    /// A single event view.
    EventView {
        /// Viewed event.
        event_id: Uuid,

        /// UTM parameters the view is attributed to.
        utm: Option<UtmParams>,
    },
    /// A single group view.
    GroupView {
        /// Viewed group.
        group_id: Uuid,
    },
}

/// Shared activity tracker handle.
pub(crate) type DynActivityTracker = Arc<dyn ActivityTracker + Send + Sync>;

/// Interface for queuing analytics activities.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait ActivityTracker {
    /// Queues an activity for later persistence.
    ///
    /// Tracking is best-effort: the call never waits for queue capacity and
    /// never fails because the tracker is saturated or stopped. Activities
    /// that cannot be queued are dropped and counted.
    async fn track(&self, activity: Activity) -> Result<()>;
}

/// Database-backed activity tracker.
pub(crate) struct ActivityTrackerDB {
    /// Channel used to queue tracked activities.
    activities_tx: mpsc::Sender<Activity>,
    /// Counters describing tracking loss, shared with the aggregator.
    stats: Arc<ActivityTrackerStats>,
}

impl ActivityTrackerDB {
    /// Create a new `ActivityTrackerDB` instance.
    pub(crate) fn new(db: DynDBActivityTracker, background_tasks: &BackgroundTasks) -> Self {
        // Setup channels and shared loss counters
        let (activities_tx, activities_rx) = mpsc::channel(ACTIVITIES_QUEUE_CAPACITY);
        let (batches_tx, batches_rx) = mpsc::channel(BATCHES_QUEUE_CAPACITY);
        let stats = Arc::new(ActivityTrackerStats::default());

        // Setup and run the worker to aggregate tracked activities
        let aggregator = Aggregator {
            batches_tx,
            cancellation_token: background_tasks.cancellation_token(),
            stats: stats.clone(),
        };
        background_tasks.spawn("activity-aggregator", async move {
            aggregator.run(activities_rx).await;
        });

        // Setup and run the worker to flush activity batches
        let flusher = Flusher { db };
        background_tasks.spawn("activity-flusher", async move {
            flusher.run(batches_rx).await;
        });

        Self {
            activities_tx,
            stats,
        }
    }
}

#[async_trait]
impl ActivityTracker for ActivityTrackerDB {
    /// [`ActivityTracker::track`].
    async fn track(&self, activity: Activity) -> Result<()> {
        // Drop the activity instead of waiting when the queue is full or closed
        if let Err(TrySendError::Full(_) | TrySendError::Closed(_)) =
            self.activities_tx.try_send(activity)
        {
            self.stats.record_dropped();
        }

        Ok(())
    }
}

/// Outcome of aggregating a single activity into a batch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AggregationOutcome {
    /// The activity was counted, but its UTM attribution was dropped.
    AttributionDropped,
    /// The activity was counted, together with its UTM attribution if any.
    Counted,
    /// The activity was dropped, together with its UTM attribution if any.
    Dropped,
}

/// Counters describing best-effort activity tracking loss.
#[derive(Debug, Default)]
struct ActivityTrackerStats {
    /// Activities dropped because the queue was saturated or a batch reached its key cap.
    dropped_events: AtomicU64,
    /// Counted views whose UTM attribution was dropped because a batch reached its UTM key cap.
    dropped_utm_attributions: AtomicU64,
}

impl ActivityTrackerStats {
    /// Returns how many activities have been dropped since the process started.
    fn dropped_events(&self) -> u64 {
        self.dropped_events.load(Ordering::Relaxed)
    }

    /// Returns how many UTM attributions have been dropped since the process started.
    fn dropped_utm_attributions(&self) -> u64 {
        self.dropped_utm_attributions.load(Ordering::Relaxed)
    }

    /// Records the loss, if any, of aggregating one activity.
    fn record_aggregation(&self, outcome: AggregationOutcome) {
        match outcome {
            AggregationOutcome::AttributionDropped => {
                self.dropped_utm_attributions.fetch_add(1, Ordering::Relaxed);
            }
            AggregationOutcome::Counted => {}
            AggregationOutcome::Dropped => self.record_dropped(),
        }
    }

    /// Records one dropped activity.
    fn record_dropped(&self) {
        self.dropped_events.fetch_add(1, Ordering::Relaxed);
    }
}

/// Worker responsible for aggregating queued activities into batches.
struct Aggregator {
    /// Channel used to hand aggregated batches to the flusher.
    batches_tx: mpsc::Sender<Batches>,
    /// Token used to signal worker shutdown.
    cancellation_token: CancellationToken,
    /// Counters describing tracking loss, shared with the tracker handle.
    stats: Arc<ActivityTrackerStats>,
}

impl Aggregator {
    /// Main worker loop: aggregates tracked activities until cancelled.
    async fn run(&self, mut activities_rx: mpsc::Receiver<Activity>) {
        let first_flush = Instant::now() + FLUSH_FREQUENCY;
        let mut flush_interval = tokio::time::interval_at(first_flush, FLUSH_FREQUENCY);
        flush_interval.set_missed_tick_behavior(MissedTickBehavior::Skip);

        let mut batches = Batches::new();
        let mut reported_dropped_events = 0;
        let mut reported_dropped_utm_attributions = 0;
        loop {
            tokio::select! {
                biased;

                // Hand the current batch to the flusher on every interval tick
                _ = flush_interval.tick() => {
                    if !batches.is_empty() {
                        batches = self.hand_over_batches(batches);
                    }
                    reported_dropped_events = self.report_dropped_events(reported_dropped_events);
                    reported_dropped_utm_attributions =
                        self.report_dropped_utm_attributions(reported_dropped_utm_attributions);
                }

                // Aggregate the next queued activity under the current day
                Some(activity) = activities_rx.recv() => {
                    self.stats.record_aggregation(batches.aggregate_activity(activity));
                }

                // Flush any pending activity before stopping the worker
                () = self.cancellation_token.cancelled() => {
                    self.drain_queued_activities(&mut batches, &mut activities_rx);

                    if !batches.is_empty() {
                        _ = self.batches_tx.send(batches).await;
                    }
                    self.report_dropped_events(reported_dropped_events);
                    self.report_dropped_utm_attributions(reported_dropped_utm_attributions);
                    break;
                }
            }
        }
    }

    /// Drains queued activities into the batches, counting the ones the caps reject.
    fn drain_queued_activities(
        &self,
        batches: &mut Batches,
        activities_rx: &mut mpsc::Receiver<Activity>,
    ) {
        while let Ok(activity) = activities_rx.try_recv() {
            self.stats.record_aggregation(batches.aggregate_activity(activity));
        }
    }

    /// Hands the batch to the flusher without waiting for a free slot.
    ///
    /// Returns the batch to keep aggregating into: an empty one after a
    /// successful hand-over, or the same batch when the flusher is still busy
    /// or gone, so pending counters keep merging until the next flush.
    fn hand_over_batches(&self, batches: Batches) -> Batches {
        match self.batches_tx.try_send(batches) {
            Ok(()) => Batches::new(),
            Err(TrySendError::Full(batches) | TrySendError::Closed(batches)) => {
                warn!(
                    pending_keys = batches.total_keys,
                    "flusher unavailable, keeping batch until the next flush"
                );
                batches
            }
        }
    }

    /// Logs the activities dropped since the last report and returns the new total.
    fn report_dropped_events(&self, reported_dropped_events: u64) -> u64 {
        let dropped_events = self.stats.dropped_events();
        if dropped_events > reported_dropped_events {
            warn!(
                dropped_events = dropped_events - reported_dropped_events,
                total_dropped_events = dropped_events,
                "activity events dropped since the last flush"
            );
        }
        dropped_events
    }

    /// Logs the UTM attributions dropped since the last report and returns the new total.
    fn report_dropped_utm_attributions(&self, reported_dropped_utm_attributions: u64) -> u64 {
        let dropped_utm_attributions = self.stats.dropped_utm_attributions();
        if dropped_utm_attributions > reported_dropped_utm_attributions {
            warn!(
                dropped_utm_attributions =
                    dropped_utm_attributions - reported_dropped_utm_attributions,
                total_dropped_utm_attributions = dropped_utm_attributions,
                "activity utm attributions dropped since the last flush"
            );
        }
        dropped_utm_attributions
    }
}

/// Worker responsible for flushing batches into the database.
struct Flusher {
    /// Database handle used for activity tracker writes.
    db: DynDBActivityTracker,
}

impl Flusher {
    /// Main worker loop: flushes aggregated batches until the channel closes.
    async fn run(&self, mut batches_rx: mpsc::Receiver<Batches>) {
        while let Some(batches) = batches_rx.recv().await {
            // Process community views
            if !batches.community_views.is_empty() {
                let data = prepare_batch_data(&batches.community_views);
                if let Err(err) = self.db.update_community_views(data).await {
                    error!(error = %format_args!("{err:#}"), "error writing community views to database");
                }
            }

            // Process event views
            if !batches.event_views.is_empty() {
                let data = prepare_batch_data(&batches.event_views);
                if let Err(err) = self.db.update_event_views(data).await {
                    error!(error = %format_args!("{err:#}"), "error writing event views to database");
                }
            }

            // Process event views attributed to UTM parameters
            if !batches.event_views_utm.is_empty() {
                let data = prepare_utm_batch_data(&batches.event_views_utm);
                if let Err(err) = self.db.update_event_views_utm(data).await {
                    error!(error = %format_args!("{err:#}"), "error writing event utm views to database");
                }
            }

            // Process group views
            if !batches.group_views.is_empty() {
                let data = prepare_batch_data(&batches.group_views);
                if let Err(err) = self.db.update_group_views(data).await {
                    error!(error = %format_args!("{err:#}"), "error writing group views to database");
                }
            }
        }
    }
}

/// Increments the counter for a key, tracking new keys against a key budget.
///
/// Returns `false` without counting when the key is new and `total_keys`
/// already reached `max_keys`.
fn increment_counter<K: Eq + Hash>(
    counters: &mut HashMap<K, Total>,
    key: K,
    total_keys: &mut usize,
    max_keys: usize,
) -> bool {
    // Reject a new key once the budget is exhausted
    if !counters.contains_key(&key) && *total_keys >= max_keys {
        return false;
    }

    // Count the activity, tracking the new key when it is one
    match counters.entry(key) {
        Entry::Occupied(mut entry) => *entry.get_mut() += 1,
        Entry::Vacant(entry) => {
            entry.insert(1);
            *total_keys += 1;
        }
    }

    true
}

/// Converts aggregated counters into sorted database-ready rows.
fn prepare_batch_data(data: &HashMap<(EntityId, Day), Total>) -> Vec<(EntityId, Day, Total)> {
    let mut db_ready_data: Vec<(EntityId, Day, Total)> = data
        .iter()
        .map(|((entity_id, day), total)| (*entity_id, day.clone(), *total))
        .collect();
    db_ready_data.sort();
    db_ready_data
}

/// Converts aggregated UTM counters into sorted database-ready rows.
///
/// Rows hold the campaign, medium, and source values in that order, with
/// missing values encoded as empty strings.
fn prepare_utm_batch_data(
    data: &HashMap<(EntityId, Day, UtmParams), Total>,
) -> Vec<(EntityId, Day, String, String, String, Total)> {
    let mut db_ready_data: Vec<(EntityId, Day, String, String, String, Total)> = data
        .iter()
        .map(|((entity_id, day, utm), total)| {
            (
                *entity_id,
                day.clone(),
                utm.campaign().unwrap_or_default().to_string(),
                utm.medium().unwrap_or_default().to_string(),
                utm.source().unwrap_or_default().to_string(),
                *total,
            )
        })
        .collect();
    db_ready_data.sort();
    db_ready_data
}

/// Aggregated in-memory batches.
#[derive(Debug, Default)]
struct Batches {
    /// Aggregated community view counts.
    community_views: HashMap<(EntityId, Day), Total>,
    /// Aggregated event view counts.
    event_views: HashMap<(EntityId, Day), Total>,
    /// Aggregated event view counts attributed to UTM parameters.
    event_views_utm: HashMap<(EntityId, Day, UtmParams), Total>,
    /// Aggregated group view counts.
    group_views: HashMap<(EntityId, Day), Total>,
    /// Distinct keys held across the view counters, bounded by [`MAX_BATCH_KEYS`].
    total_keys: usize,
    /// Distinct keys held in the UTM counters, bounded by [`MAX_BATCH_UTM_KEYS`].
    total_utm_keys: usize,
}

impl Batches {
    /// Creates a new empty batches container.
    fn new() -> Self {
        Self::default()
    }

    /// Aggregates a single activity under the current day.
    ///
    /// The activity is dropped when it introduces a new key while the batch
    /// already holds [`MAX_BATCH_KEYS`] distinct keys. Only its UTM attribution
    /// is dropped when the attribution introduces a new key while the batch
    /// already holds [`MAX_BATCH_UTM_KEYS`] UTM keys.
    fn aggregate_activity(&mut self, activity: Activity) -> AggregationOutcome {
        let day = OffsetDateTime::now_utc()
            .format(&DATE_FORMAT)
            .expect("format to succeed");

        // Select the counters and keys for the activity
        let (counters, key, utm_key) = match activity {
            Activity::CommunityView { community_id } => {
                (&mut self.community_views, (community_id, day), None)
            }
            Activity::EventView { event_id, utm } => {
                let utm_key = utm.map(|utm| (event_id, day.clone(), utm));
                (&mut self.event_views, (event_id, day), utm_key)
            }
            Activity::GroupView { group_id } => (&mut self.group_views, (group_id, day), None),
        };

        // Count the view, dropping its attribution too when it is rejected
        if !increment_counter(counters, key, &mut self.total_keys, MAX_BATCH_KEYS) {
            return AggregationOutcome::Dropped;
        }

        // Count the UTM attribution of the view under its own key budget
        if let Some(utm_key) = utm_key
            && !increment_counter(
                &mut self.event_views_utm,
                utm_key,
                &mut self.total_utm_keys,
                MAX_BATCH_UTM_KEYS,
            )
        {
            return AggregationOutcome::AttributionDropped;
        }

        AggregationOutcome::Counted
    }

    /// Returns whether there is no pending data.
    ///
    /// UTM counters are only populated alongside a view counter, so checking
    /// the view keys covers them too.
    fn is_empty(&self) -> bool {
        self.total_keys == 0
    }
}
