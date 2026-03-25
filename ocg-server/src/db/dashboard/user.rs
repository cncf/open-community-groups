//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgDB,
    templates::dashboard::user::{
        events::{UserEventsFilters, UserEventsOutput},
        invitations::{CommunityTeamInvitation, GroupTeamInvitation},
        session_proposals::{
            PendingCoSpeakerInvitation, SessionProposalInput, SessionProposalLevel, SessionProposalsFilters,
            SessionProposalsOutput,
        },
        submissions::{CfsSubmissionsFilters, CfsSubmissionsOutput},
    },
};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending community team invitation.
    async fn accept_community_team_invitation(&self, actor_user_id: Uuid, community_id: Uuid) -> Result<()>;

    /// Accepts a pending group team invitation.
    async fn accept_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Accepts a pending co-speaker invitation for a session proposal.
    async fn accept_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()>;

    /// Adds a new session proposal for the user.
    async fn add_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<Uuid>;

    /// Deletes a session proposal for the user.
    async fn delete_session_proposal(&self, actor_user_id: Uuid, session_proposal_id: Uuid) -> Result<()>;

    /// Gets the co-speaker user id for one of the user's session proposals.
    async fn get_session_proposal_co_speaker_user_id(
        &self,
        user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<Option<SessionProposalCoSpeakerUser>>;

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

    /// Lists upcoming events where the user participates.
    async fn list_user_events(&self, user_id: Uuid, filters: &UserEventsFilters) -> Result<UserEventsOutput>;

    /// Lists all pending group team invitations for the user.
    async fn list_user_group_team_invitations(&self, user_id: Uuid) -> Result<Vec<GroupTeamInvitation>>;

    /// Lists pending co-speaker invitations for the user.
    async fn list_user_pending_session_proposal_co_speaker_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<PendingCoSpeakerInvitation>>;

    /// Lists session proposals for the user.
    async fn list_user_session_proposals(
        &self,
        user_id: Uuid,
        filters: &SessionProposalsFilters,
    ) -> Result<SessionProposalsOutput>;

    /// Rejects a pending community team invitation.
    async fn reject_community_team_invitation(&self, actor_user_id: Uuid, community_id: Uuid) -> Result<()>;

    /// Rejects a pending group team invitation.
    async fn reject_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Rejects a pending co-speaker invitation for a session proposal.
    async fn reject_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()>;

    /// Resubmits a CFS submission for the user.
    async fn resubmit_cfs_submission(&self, actor_user_id: Uuid, cfs_submission_id: Uuid) -> Result<()>;

    /// Updates a session proposal for the user.
    async fn update_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<()>;

    /// Withdraws a CFS submission for the user.
    async fn withdraw_cfs_submission(&self, actor_user_id: Uuid, cfs_submission_id: Uuid) -> Result<()>;
}

#[async_trait]
impl DBDashboardUser for PgDB {
    /// [`DBDashboardUser::accept_community_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_community_team_invitation(&self, actor_user_id: Uuid, community_id: Uuid) -> Result<()> {
        self.execute(
            "select accept_community_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &community_id],
        )
        .await
    }

    /// [`DBDashboardUser::accept_group_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select accept_group_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardUser::accept_session_proposal_co_speaker_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select accept_session_proposal_co_speaker_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &session_proposal_id],
        )
        .await
    }

    /// [`DBDashboardUser::add_session_proposal`]
    #[instrument(skip(self, session_proposal), err)]
    async fn add_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select add_session_proposal($1::uuid, $2::jsonb)::uuid",
            &[&actor_user_id, &Json(session_proposal)],
        )
        .await
    }

    /// [`DBDashboardUser::delete_session_proposal`]
    #[instrument(skip(self), err)]
    async fn delete_session_proposal(&self, actor_user_id: Uuid, session_proposal_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_session_proposal($1::uuid, $2::uuid)",
            &[&actor_user_id, &session_proposal_id],
        )
        .await
    }

    /// [`DBDashboardUser::get_session_proposal_co_speaker_user_id`]
    #[instrument(skip(self), err)]
    async fn get_session_proposal_co_speaker_user_id(
        &self,
        user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<Option<SessionProposalCoSpeakerUser>> {
        let db = self.pool.get().await?;
        let row = db
            .query_opt(
                "
                select co_speaker_user_id
                from session_proposal
                where session_proposal_id = $1::uuid
                and user_id = $2::uuid
                ",
                &[&session_proposal_id, &user_id],
            )
            .await?;

        Ok(row.map(|row| SessionProposalCoSpeakerUser {
            co_speaker_user_id: row.get("co_speaker_user_id"),
        }))
    }

    /// [`DBDashboardUser::list_session_proposal_levels`]
    #[instrument(skip(self), err)]
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>> {
        self.fetch_json_one("select list_session_proposal_levels()", &[])
            .await
    }

    /// [`DBDashboardUser::list_user_cfs_submissions`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_cfs_submissions(
        &self,
        user_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput> {
        self.fetch_json_one(
            "select list_user_cfs_submissions($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_community_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_community_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CommunityTeamInvitation>> {
        self.fetch_json_one(
            "select list_user_community_team_invitations($1::uuid)",
            &[&user_id],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_events`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_events(&self, user_id: Uuid, filters: &UserEventsFilters) -> Result<UserEventsOutput> {
        self.fetch_json_one(
            "select list_user_events($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_group_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_group_team_invitations(&self, user_id: Uuid) -> Result<Vec<GroupTeamInvitation>> {
        self.fetch_json_one("select list_user_group_team_invitations($1::uuid)", &[&user_id])
            .await
    }

    /// [`DBDashboardUser::list_user_pending_session_proposal_co_speaker_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_pending_session_proposal_co_speaker_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<PendingCoSpeakerInvitation>> {
        self.fetch_json_one(
            "select list_user_pending_session_proposal_co_speaker_invitations($1::uuid)",
            &[&user_id],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_session_proposals`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_session_proposals(
        &self,
        user_id: Uuid,
        filters: &SessionProposalsFilters,
    ) -> Result<SessionProposalsOutput> {
        self.fetch_json_one(
            "select list_user_session_proposals($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::reject_community_team_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_community_team_invitation(&self, actor_user_id: Uuid, community_id: Uuid) -> Result<()> {
        self.execute(
            "select reject_community_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &community_id],
        )
        .await
    }

    /// [`DBDashboardUser::reject_group_team_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select reject_group_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &group_id],
        )
        .await
    }

    /// [`DBDashboardUser::reject_session_proposal_co_speaker_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select reject_session_proposal_co_speaker_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &session_proposal_id],
        )
        .await
    }

    /// [`DBDashboardUser::resubmit_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn resubmit_cfs_submission(&self, actor_user_id: Uuid, cfs_submission_id: Uuid) -> Result<()> {
        self.execute(
            "select resubmit_cfs_submission($1::uuid, $2::uuid)",
            &[&actor_user_id, &cfs_submission_id],
        )
        .await
    }

    /// [`DBDashboardUser::update_session_proposal`]
    #[instrument(skip(self, session_proposal), err)]
    async fn update_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<()> {
        self.execute(
            "select update_session_proposal($1::uuid, $2::uuid, $3::jsonb)",
            &[&actor_user_id, &session_proposal_id, &Json(session_proposal)],
        )
        .await
    }

    /// [`DBDashboardUser::withdraw_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn withdraw_cfs_submission(&self, actor_user_id: Uuid, cfs_submission_id: Uuid) -> Result<()> {
        self.execute(
            "select withdraw_cfs_submission($1::uuid, $2::uuid)",
            &[&actor_user_id, &cfs_submission_id],
        )
        .await
    }
}

/// Co-speaker identifier for a session proposal.
#[derive(Debug, Clone)]
pub(crate) struct SessionProposalCoSpeakerUser {
    pub co_speaker_user_id: Option<Uuid>,
}
