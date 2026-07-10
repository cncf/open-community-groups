//! Common database operations shared across different dashboards.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor, templates::dashboard::community::groups::Group, types::group::GroupParentOption,
};

/// Common database operations for dashboards.
#[async_trait]
pub(crate) trait DBDashboardCommon {
    /// Checks whether a group has active subgroups.
    async fn group_has_active_subgroups(&self, community_id: Uuid, group_id: Uuid) -> Result<bool>;

    /// Checks whether a group has any non-deleted child links.
    async fn group_has_child_links(&self, community_id: Uuid, group_id: Uuid) -> Result<bool>;

    /// Lists possible parent groups for a group relationship form field.
    async fn list_group_parent_options(
        &self,
        community_id: Uuid,
        user_id: Uuid,
        group_id: Option<Uuid>,
    ) -> Result<Vec<GroupParentOption>>;

    /// Searches for users by query.
    async fn search_user(&self, query: &str) -> Result<Vec<User>>;

    /// Updates an existing group.
    async fn update_group(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_id: Uuid,
        group: &Group,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBDashboardCommon for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBDashboardCommon::group_has_active_subgroups`]
    #[instrument(skip(self), err)]
    async fn group_has_active_subgroups(&self, community_id: Uuid, group_id: Uuid) -> Result<bool> {
        self.fetch_scalar_one(
            "select group_has_active_subgroups($1::uuid, $2::uuid)",
            &[&community_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommon::group_has_child_links`]
    #[instrument(skip(self), err)]
    async fn group_has_child_links(&self, community_id: Uuid, group_id: Uuid) -> Result<bool> {
        self.fetch_scalar_one(
            "select group_has_child_links($1::uuid, $2::uuid)",
            &[&community_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommon::list_group_parent_options`]
    #[instrument(skip(self), err)]
    async fn list_group_parent_options(
        &self,
        community_id: Uuid,
        user_id: Uuid,
        group_id: Option<Uuid>,
    ) -> Result<Vec<GroupParentOption>> {
        self.fetch_json_one(
            "select list_group_parent_options($1::uuid, $2::uuid, $3::uuid)",
            &[&community_id, &user_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardCommon::search_user`]
    #[instrument(skip(self), err)]
    async fn search_user(&self, query: &str) -> Result<Vec<User>> {
        self.fetch_json_one("select search_user($1::text)", &[&query]).await
    }

    /// [`DBDashboardCommon::update_group`]
    #[instrument(skip(self, group), err)]
    async fn update_group(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        group_id: Uuid,
        group: &Group,
    ) -> Result<()> {
        self.execute(
            "select update_group($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[&actor_user_id, &community_id, &group_id, &Json(group)],
        )
        .await
    }
}

// Types.

/// User search result.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct User {
    /// User identifier.
    pub user_id: Uuid,
    /// Unique username.
    pub username: String,

    /// Optional display name.
    pub name: Option<String>,
    /// Optional profile photo URL.
    pub photo_url: Option<String>,
}
