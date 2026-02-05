//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::user::{
        invitations::{CommunityTeamInvitation, GroupTeamInvitation},
        session_proposals::{
            SessionProposalInput, SessionProposalLevel, SessionProposalsFilters, SessionProposalsOutput,
        },
        submissions::{CfsSubmissionsFilters, CfsSubmissionsOutput},
    },
};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending community team invitation.
    async fn accept_community_team_invitation(&self, community_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Accepts a pending group team invitation.
    async fn accept_group_team_invitation(&self, group_id: Uuid, user_id: Uuid) -> Result<()>;

    /// Adds a new session proposal for the user.
    async fn add_session_proposal(
        &self,
        user_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<Uuid>;

    /// Deletes a session proposal for the user.
    async fn delete_session_proposal(&self, user_id: Uuid, session_proposal_id: Uuid) -> Result<()>;

    /// Lists all available session proposal levels.
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>>;

    /// Lists all CFS submissions for the user.
    async fn list_user_cfs_submissions(
        &self,
        user_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput>;

    /// Lists all pending community team invitations for the user.
    async fn list_user_community_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>>;

    /// Lists all pending group team invitations for the user.
    async fn list_user_group_team_invitations(&self, user_id: Uuid) -> Result<Vec<GroupTeamInvitation>>;

    /// Lists session proposals for the user.
    async fn list_user_session_proposals(
        &self,
        user_id: Uuid,
        filters: &SessionProposalsFilters,
    ) -> Result<SessionProposalsOutput>;

    /// Resubmits a CFS submission for the user.
    async fn resubmit_cfs_submission(&self, user_id: Uuid, cfs_submission_id: Uuid) -> Result<()>;

    /// Updates a session proposal for the user.
    async fn update_session_proposal(
        &self,
        user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<()>;

    /// Withdraws a CFS submission for the user.
    async fn withdraw_cfs_submission(&self, user_id: Uuid, cfs_submission_id: Uuid) -> Result<()>;
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

    /// [`DBDashboardUser::add_session_proposal`]
    #[instrument(skip(self, session_proposal), err)]
    async fn add_session_proposal(
        &self,
        user_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<Uuid> {
        trace!("db: add session proposal");

        let db = self.pool.get().await?;
        let id = db
            .query_one(
                "select add_session_proposal($1::uuid, $2::jsonb)::uuid",
                &[&user_id, &Json(session_proposal)],
            )
            .await?
            .get(0);

        Ok(id)
    }

    /// [`DBDashboardUser::delete_session_proposal`]
    #[instrument(skip(self), err)]
    async fn delete_session_proposal(&self, user_id: Uuid, session_proposal_id: Uuid) -> Result<()> {
        trace!("db: delete session proposal");

        let db = self.pool.get().await?;
        db.execute(
            "select delete_session_proposal($1::uuid, $2::uuid)",
            &[&user_id, &session_proposal_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardUser::list_session_proposal_levels`]
    #[instrument(skip(self), err)]
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>> {
        trace!("db: list session proposal levels");

        let db = self.pool.get().await?;
        let row = db
            .query_one("select list_session_proposal_levels()::text", &[])
            .await?;
        let levels: Vec<SessionProposalLevel> = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(levels)
    }

    /// [`DBDashboardUser::list_user_cfs_submissions`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_cfs_submissions(
        &self,
        user_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput> {
        trace!("db: list user cfs submissions");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_cfs_submissions($1::uuid, $2::jsonb)::text",
                &[&user_id, &Json(filters)],
            )
            .await?;
        let submissions: CfsSubmissionsOutput = serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(submissions)
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

    /// [`DBDashboardUser::list_user_session_proposals`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_session_proposals(
        &self,
        user_id: Uuid,
        filters: &SessionProposalsFilters,
    ) -> Result<SessionProposalsOutput> {
        trace!("db: list user session proposals");

        let db = self.pool.get().await?;
        let row = db
            .query_one(
                "select list_user_session_proposals($1::uuid, $2::jsonb)::text",
                &[&user_id, &Json(filters)],
            )
            .await?;
        let session_proposals_output: SessionProposalsOutput =
            serde_json::from_str(&row.get::<_, String>(0))?;

        Ok(session_proposals_output)
    }

    /// [`DBDashboardUser::resubmit_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn resubmit_cfs_submission(&self, user_id: Uuid, cfs_submission_id: Uuid) -> Result<()> {
        trace!("db: resubmit cfs submission");

        let db = self.pool.get().await?;
        db.execute(
            "select resubmit_cfs_submission($1::uuid, $2::uuid)",
            &[&user_id, &cfs_submission_id],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardUser::update_session_proposal`]
    #[instrument(skip(self, session_proposal), err)]
    async fn update_session_proposal(
        &self,
        user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<()> {
        trace!("db: update session proposal");

        let db = self.pool.get().await?;
        db.execute(
            "select update_session_proposal($1::uuid, $2::uuid, $3::jsonb)",
            &[&user_id, &session_proposal_id, &Json(session_proposal)],
        )
        .await?;

        Ok(())
    }

    /// [`DBDashboardUser::withdraw_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn withdraw_cfs_submission(&self, user_id: Uuid, cfs_submission_id: Uuid) -> Result<()> {
        trace!("db: withdraw cfs submission");

        let db = self.pool.get().await?;
        db.execute(
            "select withdraw_cfs_submission($1::uuid, $2::uuid)",
            &[&user_id, &cfs_submission_id],
        )
        .await?;

        Ok(())
    }
}
