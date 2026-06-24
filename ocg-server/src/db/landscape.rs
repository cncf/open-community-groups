//! Database operations for landscape entries.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    types::landscape::{
        DashboardLandscapeFilters, LandscapeEntryInput, LandscapeFilters, LandscapeOutput,
        parse_tags,
    },
};

/// Database operations for the landscape product area.
#[async_trait]
pub(crate) trait DBLandscape {
    /// Search published landscape entries.
    async fn search_landscape_entries(&self, filters: &LandscapeFilters)
    -> Result<LandscapeOutput>;

    /// List entries for one alliance dashboard.
    async fn list_alliance_landscape_entries(
        &self,
        alliance_id: Uuid,
        filters: &DashboardLandscapeFilters,
    ) -> Result<LandscapeOutput>;

    /// Add a landscape entry to an alliance.
    async fn add_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        input: &LandscapeEntryInput,
    ) -> Result<Uuid>;

    /// Update a landscape entry.
    async fn update_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
        input: &LandscapeEntryInput,
    ) -> Result<()>;

    /// Delete a landscape entry.
    async fn delete_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
    ) -> Result<()>;

    /// Toggle landscape entry publishing status.
    async fn update_landscape_entry_published(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
        published: bool,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBLandscape for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self, filters), err)]
    async fn search_landscape_entries(
        &self,
        filters: &LandscapeFilters,
    ) -> Result<LandscapeOutput> {
        self.fetch_json_one(
            "select search_landscape_entries($1::jsonb)",
            &[&Json(filters)],
        )
        .await
    }

    #[instrument(skip(self, filters), err)]
    async fn list_alliance_landscape_entries(
        &self,
        alliance_id: Uuid,
        filters: &DashboardLandscapeFilters,
    ) -> Result<LandscapeOutput> {
        self.fetch_json_one(
            "select list_alliance_landscape_entries($1::uuid, $2::jsonb)",
            &[&alliance_id, &Json(filters)],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        input: &LandscapeEntryInput,
    ) -> Result<Uuid> {
        let tags = parse_tags(input.tags.as_deref());
        self.fetch_scalar_one(
            "select add_landscape_entry($1::uuid, $2::uuid, $3::jsonb, $4::text[])",
            &[&actor_user_id, &alliance_id, &Json(input), &tags],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
        input: &LandscapeEntryInput,
    ) -> Result<()> {
        let tags = parse_tags(input.tags.as_deref());
        self.execute(
            "select update_landscape_entry($1::uuid, $2::uuid, $3::uuid, $4::jsonb, $5::text[])",
            &[&actor_user_id, &alliance_id, &entry_id, &Json(input), &tags],
        )
        .await?;
        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn delete_landscape_entry(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select delete_landscape_entry($1::uuid, $2::uuid, $3::uuid)",
            &[&actor_user_id, &alliance_id, &entry_id],
        )
        .await?;
        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn update_landscape_entry_published(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        entry_id: Uuid,
        published: bool,
    ) -> Result<()> {
        self.execute(
            "select update_landscape_entry_published($1::uuid, $2::uuid, $3::uuid, $4::boolean)",
            &[&actor_user_id, &alliance_id, &entry_id, &published],
        )
        .await?;
        Ok(())
    }
}
