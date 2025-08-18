//! This module defines database functionality for the event page.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{db::PgDB, types::event::EventFull};

/// Database trait defining all data access operations for event page.
#[async_trait]
pub(crate) trait DBEvent {
    /// Retrieves detailed event information.
    async fn get_event(&self, community_id: Uuid, group_slug: &str, event_slug: &str) -> Result<EventFull>;
}

#[async_trait]
impl DBEvent for PgDB {
    /// [`DB::get_event`]
    #[instrument(skip(self), err)]
    async fn get_event(&self, community_id: Uuid, group_slug: &str, event_slug: &str) -> Result<EventFull> {
        trace!("db: get event");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select get_event($1::uuid, $2::text, $3::text)::text",
                &[&community_id, &group_slug, &event_slug],
            )
            .await?;
        let event = EventFull::try_from_json(row.get(0))?;

        Ok(event)
    }
}
