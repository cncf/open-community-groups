//! Common database operations shared across different modules.

use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use cached::proc_macro::cached;
use deadpool_postgres::Client;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    types::{community::Community, event::EventFull, group::GroupFull},
};

/// Common database operations trait.
#[async_trait]
pub(crate) trait DBCommon {
    /// Retrieves community information by its unique identifier.
    async fn get_community(&self, community_id: Uuid) -> Result<Community>;

    /// Gets full event details.
    async fn get_event_full(&self, event_id: Uuid) -> Result<EventFull>;

    /// Gets group full details.
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull>;

    /// Lists all available timezones.
    async fn list_timezones(&self) -> Result<Vec<String>>;
}

#[async_trait]
impl DBCommon for PgDB {
    /// [`DBCommon::get_community`]
    #[instrument(skip(self), err)]
    async fn get_community(&self, community_id: Uuid) -> Result<Community> {
        trace!("db: get community");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_community($1::uuid)::text", &[&community_id])
            .await?;
        let community = Community::try_from_json(&row.get::<_, String>(0))?;

        Ok(community)
    }

    /// [`DBCommon::get_event_full`]
    #[instrument(skip(self), err)]
    async fn get_event_full(&self, event_id: Uuid) -> Result<EventFull> {
        trace!("db: get event full");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_event_full($1::uuid)::text", &[&event_id])
            .await?;
        let event = EventFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(event)
    }

    /// [`DBCommon::get_group_full`]
    #[instrument(skip(self), err)]
    async fn get_group_full(&self, group_id: Uuid) -> Result<GroupFull> {
        trace!("db: get group full");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select get_group_full($1::uuid)::text", &[&group_id])
            .await?;
        let group = GroupFull::try_from_json(&row.get::<_, String>(0))?;

        Ok(group)
    }

    /// [`DBCommon::list_timezones`]
    #[instrument(skip(self), err)]
    async fn list_timezones(&self) -> Result<Vec<String>> {
        #[cached(
            time = 86400,
            key = "String",
            convert = r#"{ String::from("timezones") }"#,
            sync_writes = "by_key",
            result = true
        )]
        async fn inner(db: Client) -> Result<Vec<String>> {
            trace!("db: list timezones");

            let timezones = db
                .query(
                    "
                    select name
                    from pg_timezone_names
                    where name not like 'posix%'
                    and name not like 'SystemV%'
                    order by name asc;
                    ",
                    &[],
                )
                .await?
                .into_iter()
                .map(|row| row.get("name"))
                .collect();

            Ok(timezones)
        }

        let db = self.pool.get().await?;
        inner(db).await
    }
}
