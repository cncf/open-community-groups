//! Common database operations shared across different dashboards.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{db::PgExecutor, templates::dashboard::alliance::groups::Group};

/// Common database operations for dashboards.
#[async_trait]
pub(crate) trait DBDashboardCommon {
    /// Searches for users by query.
    async fn search_user(&self, query: &str) -> Result<Vec<User>>;

    /// Records an admin-curated intentional dating introduction.
    async fn add_intentional_dating_intro(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        first_user_id: Uuid,
        second_user_id: Uuid,
        admin_notes: Option<String>,
    ) -> Result<Uuid>;

    /// Lists private intentional dating opt-ins visible to authorized admins.
    async fn list_intentional_dating_opt_ins(
        &self,
        alliance_id: Uuid,
        group_id: Option<Uuid>,
    ) -> Result<Vec<IntentionalDatingOptIn>>;

    /// Updates an existing group.
    async fn update_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        group: &Group,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBDashboardCommon for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBDashboardCommon::search_user`]
    #[instrument(skip(self), err)]
    async fn search_user(&self, query: &str) -> Result<Vec<User>> {
        self.fetch_json_one("select search_user($1::text)", &[&query]).await
    }

    /// [`DBDashboardCommon::add_intentional_dating_intro`]
    #[instrument(skip(self, admin_notes), err)]
    async fn add_intentional_dating_intro(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        first_user_id: Uuid,
        second_user_id: Uuid,
        admin_notes: Option<String>,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            select add_intentional_dating_intro(
                $1::uuid,
                $2::uuid,
                $3::uuid,
                $4::uuid,
                $5::uuid,
                $6::text
            )
            "#,
            &[
                &actor_user_id,
                &alliance_id,
                &group_id,
                &first_user_id,
                &second_user_id,
                &admin_notes,
            ],
        )
        .await
    }

    /// [`DBDashboardCommon::list_intentional_dating_opt_ins`]
    #[instrument(skip(self), err)]
    async fn list_intentional_dating_opt_ins(
        &self,
        alliance_id: Uuid,
        group_id: Option<Uuid>,
    ) -> Result<Vec<IntentionalDatingOptIn>> {
        self.fetch_json_one(
            "select list_intentional_dating_opt_ins($1::uuid, $2::uuid)",
            &[&alliance_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommon::update_group`]
    #[instrument(skip(self, group), err)]
    async fn update_group(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        group: &Group,
    ) -> Result<()> {
        self.execute(
            "select update_group($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[&actor_user_id, &alliance_id, &group_id, &Json(group)],
        )
        .await
    }
}

// Types.

/// User search result.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct User {
    pub user_id: Uuid,
    pub username: String,

    pub name: Option<String>,
    pub photo_url: Option<String>,
}

/// Private intentional dating opt-in visible only to authorized admins.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct IntentionalDatingOptIn {
    pub user_id: Uuid,
    pub username: String,
    pub group_id: Uuid,
    pub group_name: String,
    pub alliance_id: Uuid,
    pub alliance_display_name: String,

    pub city: Option<String>,
    pub company: Option<String>,
    pub country: Option<String>,
    pub email: Option<String>,
    pub intentional_dating_goals: Option<String>,
    pub intentional_dating_preferences: Option<String>,
    pub name: Option<String>,
    pub photo_url: Option<String>,
    pub title: Option<String>,
}
