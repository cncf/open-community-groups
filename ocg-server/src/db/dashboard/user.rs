//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::user::invitations::{CommunityTeamInvitation, GroupTeamInvitation},
};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending community team invitation.
    async fn accept_community_team_invitation(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Accepts a pending group team invitation.
    async fn accept_group_team_invitation(&self, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Lists all pending community team invitations for the user.
    async fn list_user_community_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>>;

    /// Lists all pending group team invitations for the user.
    async fn list_user_group_team_invitations(&self, user_id: Uuid) -> Result<Vec<GroupTeamInvitation>>;
}

#[async_trait]
impl DBDashboardUser for PgDB {
    /// [`DBDashboardUser::accept_community_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_community_team_invitation(&self, community_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: accept community team invitation");

        let db = self.pool.get().await?;
        db.execute(
            "select accept_community_team_invitation($1::uuid, $2::uuid)",
            &[&community_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardUser::accept_group_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_group_team_invitation(&self, group_id: Uuid, user_id: Uuid) -> Result<()> {
        trace!("db: accept group team invitation");

        let db = self.pool.get().await?;
        db.execute(
            "select accept_group_team_invitation($1::uuid, $2::uuid)",
            &[&group_id, &user_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardUser::list_user_community_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_community_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>> {
        trace!("db: list user community team invitations");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_community_team_invitations($1::uuid)::text",
                &[&user_id],
            )
            .await?;
        let invitations: Vec<CommunityTeamInvitation> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(invitations)
    }

    /// [`DBDashboardUser::list_user_group_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_group_team_invitations(&self, user_id: Uuid) -> Result<Vec<GroupTeamInvitation>> {
        trace!("db: list user group team invitations");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_group_team_invitations($1::uuid)::text",
                &[&user_id],
            )
            .await?;
        let invitations: Vec<GroupTeamInvitation> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(invitations)
    }
}
