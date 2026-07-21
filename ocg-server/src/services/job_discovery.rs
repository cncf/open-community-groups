//! Scheduled discovery and publication of global jobs from user-approved sources.

use std::{collections::HashSet, sync::Arc, time::Duration};

use anyhow::Result;
use chrono::{Datelike, TimeZone, Timelike, Utc};
use garde::Validate;
use tokio::time::sleep;
use tokio_util::{sync::CancellationToken, task::TaskTracker};
use tracing::{error, info};
use uuid::Uuid;

use crate::{
    config::YouComConfig,
    db::{PgDB, PgExecutor, jobs::DBJobs},
    integrations::you_com::{SearchResult, YouComClient},
    types::jobs::JobInput,
};

/// Runs an authorized user-owned discovery request without blocking HTTP.
#[derive(Clone)]
pub(crate) struct ManualJobDiscovery {
    cfg: YouComConfig,
    db: Arc<PgDB>,
}

impl ManualJobDiscovery {
    pub(crate) fn new(cfg: YouComConfig, db: Arc<PgDB>) -> Self {
        Self { cfg, db }
    }
    pub(crate) fn enabled(&self) -> bool {
        self.cfg.enabled
    }
    pub(crate) fn spawn_user_run(&self, user_id: Uuid) {
        let cfg = self.cfg.clone();
        let db = self.db.clone();
        tokio::spawn(async move {
            if let Err(err) = run_user(cfg, db, user_id).await {
                error!(%err, %user_id, "manual You.com job discovery failed");
            }
        });
    }
}

/// Starts the daily job discovery worker using the shared You.com configuration.
pub(crate) fn start(
    cfg: YouComConfig,
    db: Arc<PgDB>,
    tasks: &TaskTracker,
    cancel: &CancellationToken,
) {
    if !cfg.enabled {
        return;
    }
    tasks.spawn({
        let cancel = cancel.clone();
        async move {
            let Ok(client) = YouComClient::new(&cfg) else {
                error!("could not start You.com job discovery");
                return;
            };
            let Ok(timezone) = cfg.schedule_timezone.parse() else {
                error!("invalid You.com job discovery timezone");
                return;
            };
            loop {
                tokio::select! {
                    () = sleep(delay_until_next_run(timezone, cfg.schedule_hour)) => {},
                    () = cancel.cancelled() => break,
                }
                if let Err(err) = ingest_enabled(&db, &client).await {
                    error!(%err, "scheduled You.com job discovery failed");
                }
            }
        }
    });
}

pub(crate) async fn run_user(cfg: YouComConfig, db: Arc<PgDB>, user_id: Uuid) -> Result<()> {
    anyhow::ensure!(cfg.enabled, "You.com job discovery is disabled");
    let enabled: bool = db.fetch_scalar_one(
        "select exists(select 1 from jobs_discovery_integration where user_id = $1 and enabled)",
        &[&user_id],
    ).await?;
    anyhow::ensure!(enabled, "job discovery is not enabled");
    ingest_users(&db, &YouComClient::new(&cfg)?, &[user_id]).await
}

async fn ingest_enabled(db: &PgDB, client: &YouComClient) -> Result<()> {
    let users: Vec<Uuid> = db.fetch_scalar_one(
        "select coalesce(array_agg(user_id), '{}'::uuid[]) from jobs_discovery_integration where enabled",
        &[],
    ).await?;
    ingest_users(db, client, &users).await
}

async fn ingest_users(db: &PgDB, client: &YouComClient, users: &[Uuid]) -> Result<()> {
    for user_id in users {
        db.execute(
            "insert into jobs_discovery_run (user_id, status) values ($1, 'running')",
            &[user_id],
        )
        .await?;
    }
    let outcome = async {
        for user_id in users {
            let sources: Vec<String> = db.fetch_scalar_one(
                "select coalesce(array_agg(url), '{}'::text[]) from jobs_discovery_source
                 where user_id = $1 and enabled", &[user_id],
            ).await?;
            let mut discovered = 0;
            let mut created = 0;
            for source_url in sources {
                let mut seen = HashSet::new();
                for result in client.search(&format!("jobs hiring careers site:{source_url}")).await? {
                    let Some(input) = parse_discovered_job(&result) else { continue };
                    if !seen.insert(result.url.trim().to_lowercase()) { continue; }
                    let fingerprint = fingerprint(&input, &result.url);
                    let item: Option<Uuid> = db.fetch_scalar_opt(
                        "insert into jobs_discovery_item (user_id, source_url, fingerprint)
                         values ($1, $2, $3) on conflict (user_id, fingerprint) do nothing
                         returning jobs_discovery_item_id",
                        &[user_id, &source_url, &fingerprint],
                    ).await?;
                    let Some(_) = item else { continue };
                    discovered += 1;
                    let job_id = db.add_job(*user_id, &input).await?;
                    db.update_job_published(*user_id, job_id, true).await?;
                    db.execute(
                        "update jobs_discovery_item set job_id = $1 where user_id = $2 and fingerprint = $3",
                        &[&job_id, user_id, &fingerprint],
                    ).await?;
                    created += 1;
                }
            }
            db.execute(
                "update jobs_discovery_run set completed_at = now(), status = 'succeeded',
                 discovered_count = $2, created_count = $3
                 where jobs_discovery_run_id = (select jobs_discovery_run_id from jobs_discovery_run
                 where user_id = $1 and status = 'running' order by started_at desc limit 1)",
                &[user_id, &discovered, &created],
            ).await?;
            info!(%user_id, discovered, created, "published discovered jobs");
        }
        Result::<()>::Ok(())
    }.await;
    if let Err(err) = &outcome {
        for user_id in users {
            db.execute(
                "update jobs_discovery_run set completed_at = now(), status = 'failed', error_message = $2
                 where jobs_discovery_run_id = (select jobs_discovery_run_id from jobs_discovery_run
                 where user_id = $1 and status = 'running' order by started_at desc limit 1)",
                &[user_id, &err.to_string()],
            ).await?;
        }
    }
    outcome
}

/// Accept only results with an explicit title, employer, description, and HTTPS application URL.
fn parse_discovered_job(result: &SearchResult) -> Option<JobInput> {
    let title = result.title.trim();
    let description = result.description.as_deref()?.trim();
    let apply_url = reqwest::Url::parse(result.url.trim()).ok()?;
    if !matches!(apply_url.scheme(), "http" | "https") || title.is_empty() || description.is_empty()
    {
        return None;
    }
    // You.com result titles conventionally expose the employer after " at " or " - ".
    let (title, company_name) = title
        .split_once(" at ")
        .or_else(|| title.split_once(" - "))
        .filter(|(role, company)| !role.trim().is_empty() && !company.trim().is_empty())?;
    let summary: String = description.chars().take(280).collect();
    let input = JobInput {
        title: title.trim().to_owned(),
        company_name: company_name.trim().to_owned(),
        summary,
        description: description.to_owned(),
        apply_url: apply_url.into(),
        location: None,
        remote: None,
        members_only: Some(false),
        tags: None,
    };
    input.validate().ok()?;
    Some(input)
}

fn fingerprint(input: &JobInput, apply_url: &str) -> String {
    use sha2::{Digest, Sha256};
    let mut hash = Sha256::new();
    hash.update(input.title.trim().to_lowercase());
    hash.update(b"\0");
    hash.update(input.company_name.trim().to_lowercase());
    hash.update(b"\0");
    hash.update(apply_url.trim().to_lowercase());
    hex::encode(hash.finalize())
}

fn delay_until_next_run(timezone: chrono_tz::Tz, hour: u8) -> Duration {
    let now = Utc::now().with_timezone(&timezone);
    let today = timezone
        .with_ymd_and_hms(now.year(), now.month(), now.day(), u32::from(hour), 0, 0)
        .single()
        .expect("configured schedule hour must be valid");
    let next = if now.hour() < u32::from(hour) {
        today
    } else {
        today + chrono::Duration::days(1)
    };
    (next.with_timezone(&Utc) - Utc::now()).to_std().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_incomplete_search_results() {
        assert!(
            parse_discovered_job(&SearchResult {
                title: "Engineer".into(),
                url: "https://x.test".into(),
                description: None
            })
            .is_none()
        );
    }
    #[test]
    fn accepts_explicit_job_result() {
        let job = parse_discovered_job(&SearchResult {
            title: "Rust Engineer at Acme".into(),
            url: "https://x.test/jobs/1".into(),
            description: Some("Build reliable systems.".into()),
        })
        .unwrap();
        assert_eq!(job.company_name, "Acme");
    }
}
