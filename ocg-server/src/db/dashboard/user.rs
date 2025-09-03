//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{db::PgDB, templates::dashboard::user::invitations::CommunityTeamInvitation};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending community team invitation.
    async fn accept_community_team_invitation(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Lists pending community team invitations for the user.
    async fn list_user_community_team_invitations(
        &self,
        community_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>>;
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

    /// [`DBDashboardUser::list_user_community_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_community_team_invitations(
        &self,
        community_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>> {
        trace!("db: list user community team invitations");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_community_team_invitations($1::uuid, $2::uuid)::text",
                &[&community_id, &user_id],
            )
            .await?;
        let invitations: Vec<CommunityTeamInvitation> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(invitations)
    }
}
