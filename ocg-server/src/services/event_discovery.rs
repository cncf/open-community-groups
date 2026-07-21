//! Scheduled discovery of Baku community-event pages.

use std::time::Duration;

use chrono::{DateTime, Datelike, TimeZone, Timelike, Utc};
use serde::Deserialize;
use serde_json::Value;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, info};
use uuid::Uuid;

use crate::{
    config::YouComConfig,
    db::{PgDB, PgExecutor, dashboard::group::DBDashboardGroup},
    integrations::you_com::{DiscoveredEvent, SearchResult, YouComClient, unique_baku_results},
};

/// Executes authorized, on-demand discovery runs from the dashboard.
#[derive(Clone)]
pub(crate) struct ManualEventDiscovery {
    cfg: YouComConfig,
    db: std::sync::Arc<PgDB>,
}

impl ManualEventDiscovery {
    /// Creates a runner when You.com discovery is configured.
    pub(crate) fn new(cfg: YouComConfig, db: std::sync::Arc<PgDB>) -> Self {
        Self { cfg, db }
    }

    /// Starts a group-specific discovery run without blocking the HTTP request.
    pub(crate) fn spawn_group_run(&self, group_id: Uuid) {
        let cfg = self.cfg.clone();
        let db = self.db.clone();
        tokio::spawn(async move {
            if let Err(err) = run_group(cfg, db, group_id).await {
                error!(%err, %group_id, "manual You.com event discovery failed");
            }
        });
    }

    /// Returns whether dashboard-initiated discovery is enabled.
    pub(crate) fn enabled(&self) -> bool {
        self.cfg.enabled
    }
}

/// Starts the daily discovery worker when the You.com integration is enabled.
pub(crate) fn start(
    cfg: YouComConfig,
    db: std::sync::Arc<PgDB>,
    task_tracker: &TaskTracker,
    cancellation_token: &CancellationToken,
) {
    if !cfg.enabled {
        return;
    }

    task_tracker.spawn({
        let cancellation_token = cancellation_token.clone();
        async move {
            let client = match YouComClient::new(&cfg) {
                Ok(client) => client,
                Err(err) => {
                    error!(%err, "could not start You.com event discovery");
                    return;
                }
            };
            let timezone = match cfg.schedule_timezone.parse() {
                Ok(timezone) => timezone,
                Err(err) => {
                    error!(%err, "invalid You.com event discovery timezone");
                    return;
                }
            };

            loop {
                let delay = delay_until_next_run(timezone, cfg.schedule_hour);
                tokio::select! {
                    () = sleep(delay) => {},
                    () = cancellation_token.cancelled() => break,
                }

                if let Err(err) = ingest_configured_sources(&db, &client).await {
                    error!(%err, "You.com Baku event discovery failed");
                }
            }
        }
    });
}

/// Runs discovery immediately for one enabled group.
pub(crate) async fn run_group(
    cfg: YouComConfig,
    db: std::sync::Arc<PgDB>,
    group_id: Uuid,
) -> anyhow::Result<()> {
    anyhow::ensure!(cfg.enabled, "You.com event discovery is disabled");
    let integration_enabled: bool = db
        .fetch_scalar_one(
            "select exists(
                select 1 from group_event_integration
                where group_id = $1 and enabled
            )",
            &[&group_id],
        )
        .await?;
    anyhow::ensure!(
        integration_enabled,
        "event discovery is not enabled for this group"
    );
    let client = YouComClient::new(&cfg)?;
    ingest_sources(&db, &client, &[group_id]).await
}

#[derive(Debug, Deserialize)]
struct Source {
    created_by_user_id: Uuid,
    city: String,
    group_id: Uuid,
    timezone: String,
    url: String,
}

async fn ingest_configured_sources(db: &PgDB, client: &YouComClient) -> anyhow::Result<()> {
    let run_group_ids: Vec<Uuid> = db
        .fetch_scalar_one(
            "select coalesce(array_agg(group_id), '{}'::uuid[])
             from group_event_integration where enabled",
            &[],
        )
        .await?;
    ingest_sources(db, client, &run_group_ids).await
}

/// Ingests sources and records runs for the supplied enabled groups.
async fn ingest_sources(
    db: &PgDB,
    client: &YouComClient,
    run_group_ids: &[Uuid],
) -> anyhow::Result<()> {
    for group_id in run_group_ids {
        db.execute(
            "insert into group_event_integration_run (group_id, status) values ($1, 'running')",
            &[group_id],
        )
        .await?;
    }

    let sources: Vec<Source> = db
        .fetch_json_one(
            "select coalesce(jsonb_agg(jsonb_build_object(
                'created_by_user_id', i.created_by_user_id,
                'city', i.city,
                'group_id', s.group_id,
                'timezone', i.timezone,
                'url', s.url
            )), '[]'::jsonb)
             from group_event_integration_source s
             join group_event_integration i using (group_id)
             where s.enabled and i.enabled
               and s.group_id = any($1::uuid[])",
            &[&run_group_ids],
        )
        .await?;

    let mut counts = std::collections::HashMap::<Uuid, (i32, i32)>::new();
    let result = async {
    for source in sources {
        let results = unique_baku_results(
            client
                .search(&format!("Baku Azerbaijan events site:{}", source.url))
                .await?,
        );
        for result in results {
            let Some(event) = parse_discovered_event(&result, &source.url) else {
                continue;
            };
            let fingerprint = event.fingerprint();
            let inserted: Option<Uuid> = db
                .fetch_scalar_opt(
                    "insert into group_event_integration_item (group_id, source_url, fingerprint)
                     values ($1, $2, $3) on conflict (group_id, fingerprint) do nothing
                     returning group_event_integration_item_id",
                    &[&source.group_id, &source.url, &fingerprint],
                )
                .await?;
            if inserted.is_none() {
                continue;
            }
            let count = counts.entry(source.group_id).or_default();
            count.0 += 1;
            if let Some(event_id) = create_and_publish_event(db, &source, &event).await? {
                db.execute(
                    "update group_event_integration_item set event_id = $1
                     where group_id = $2 and fingerprint = $3",
                    &[&event_id, &source.group_id, &fingerprint],
                )
                .await?;
                count.1 += 1;
            }
        }
        info!(group_id = %source.group_id, source_url = %source.url, "ingested event discovery candidates");
    }
    anyhow::Ok(())
    }.await;

    for group_id in run_group_ids {
        let (discovered_count, created_count) = counts.get(&group_id).copied().unwrap_or_default();
        match &result {
            Ok(()) => {
                db.execute(
                    "update group_event_integration_run
                 set completed_at = now(), status = 'succeeded',
                     discovered_count = $2, created_count = $3
                 where group_event_integration_run_id = (
                     select group_event_integration_run_id from group_event_integration_run
                     where group_id = $1 and status = 'running'
                     order by started_at desc limit 1
                 )",
                    &[&group_id, &discovered_count, &created_count],
                )
                .await?
            }
            Err(err) => {
                db.execute(
                    "update group_event_integration_run
                 set completed_at = now(), status = 'failed', error_message = $2
                 where group_event_integration_run_id = (
                     select group_event_integration_run_id from group_event_integration_run
                     where group_id = $1 and status = 'running'
                     order by started_at desc limit 1
                 )",
                    &[&group_id, &err.to_string()],
                )
                .await?
            }
        };
    }
    result?;
    Ok(())
}

/// Extract only events with an explicit RFC3339 date from the search response.
///
/// We intentionally reject ambiguous natural-language dates: they are locale-dependent and
/// cannot safely be published without a human review step.
fn parse_discovered_event(result: &SearchResult, source_url: &str) -> Option<DiscoveredEvent> {
    let title = result.title.trim();
    if title.is_empty() || title.len() > 240 {
        return None;
    }
    let description = result
        .description
        .as_deref()
        .map(str::trim)
        .filter(|text| !text.is_empty());
    let starts_at = description?
        .split_whitespace()
        .map(|word| {
            word.trim_matches(|c: char| {
                !c.is_ascii_alphanumeric() && c != ':' && c != '+' && c != '-'
            })
        })
        .find_map(|word| DateTime::parse_from_rfc3339(word).ok())
        .map(|time| time.with_timezone(&Utc))?;
    if starts_at <= Utc::now() {
        return None;
    }
    Some(DiscoveredEvent {
        title: title.to_owned(),
        description: description.map(str::to_owned),
        starts_at,
        source_url: source_url.to_owned(),
    })
}

/// Creates from an organizer-configured event-default payload, never guessed fields.
async fn create_and_publish_event(
    db: &PgDB,
    source: &Source,
    discovered: &DiscoveredEvent,
) -> anyhow::Result<Option<Uuid>> {
    let Some(Value::Object(mut payload)) = db
        .fetch_json_opt(
            "select event_defaults from \"group\" where group_id = $1",
            &[&source.group_id],
        )
        .await?
    else {
        return Ok(None);
    };
    let timezone: chrono_tz::Tz = source.timezone.parse()?;
    let starts_at = discovered.starts_at.with_timezone(&timezone);
    let ends_at = starts_at + chrono::Duration::hours(2);
    payload.insert("name".into(), Value::String(discovered.title.clone()));
    payload.insert(
        "description".into(),
        Value::String(format!(
            "{}\n\nSource: {}",
            discovered.description.as_deref().unwrap_or_default(),
            discovered.source_url
        )),
    );
    payload.insert("timezone".into(), Value::String(source.timezone.clone()));
    payload.insert(
        "starts_at".into(),
        Value::String(starts_at.format("%F %T").to_string()),
    );
    payload.insert(
        "ends_at".into(),
        Value::String(ends_at.format("%F %T").to_string()),
    );
    payload.insert("venue_city".into(), Value::String(source.city.clone()));
    payload.insert("test_event".into(), Value::Bool(false));
    let event_id = db
        .add_event(
            source.created_by_user_id,
            source.group_id,
            &Value::Object(payload),
            &Default::default(),
        )
        .await?;
    db.publish_event(source.created_by_user_id, None, source.group_id, event_id)
        .await?;
    Ok(Some(event_id))
}

fn delay_until_next_run(timezone: chrono_tz::Tz, hour: u8) -> Duration {
    let now = Utc::now().with_timezone(&timezone);
    let today = timezone
        .with_ymd_and_hms(now.year(), now.month(), now.day(), u32::from(hour), 0, 0)
        .single()
        .expect("configured timezone must have a valid scheduled hour");
    let next = if now.hour() < u32::from(hour) {
        today
    } else {
        today + chrono::Duration::days(1)
    };
    (next.with_timezone(&Utc) - Utc::now())
        .to_std()
        .unwrap_or_else(|_| Duration::from_secs(0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn next_run_delay_is_bounded_by_one_day() {
        let delay = delay_until_next_run(chrono_tz::Asia::Baku, 9);
        assert!(delay <= Duration::from_secs(24 * 60 * 60));
    }

    #[test]
    fn rejects_ambiguous_event_dates() {
        let result = SearchResult {
            title: "Baku Rust meetup".into(),
            url: "https://example.test/event".into(),
            description: Some("Join us next Thursday in Baku".into()),
        };
        assert!(parse_discovered_event(&result, "https://example.test").is_none());
    }

    #[test]
    fn parses_explicit_future_rfc3339_date() {
        let result = SearchResult {
            title: "Baku Rust meetup".into(),
            url: "https://example.test/event".into(),
            description: Some("Starts 2099-07-21T12:00:00Z in Baku".into()),
        };
        let event = parse_discovered_event(&result, "https://example.test").unwrap();
        assert_eq!(event.title, "Baku Rust meetup");
    }
}
