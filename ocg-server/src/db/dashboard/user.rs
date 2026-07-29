//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    templates::dashboard::{
        audit::{AuditLogFilters, AuditLogsOutput},
        user::{
            events::{UserEventsFilters, UserEventsOutput},
            groups::{UserGroupsFilters, UserGroupsOutput},
            invitations::{CommunityTeamInvitation, EventInvitation, GroupTeamInvitation},
            session_proposals::{
                PendingCoSpeakerInvitation, SessionProposalInput, SessionProposalLevel,
                SessionProposalsFilters, SessionProposalsOutput,
            },
            submissions::{CfsSubmissionsFilters, CfsSubmissionsOutput},
        },
    },
    types::{
        badges::{UserBadge, UserBadgeIdentity},
        event::EventEnrollmentReconciliationOutcome,
        payments::PaymentProvider,
        questionnaire::QuestionnaireAnswers,
    },
};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending community team invitation.
    async fn accept_community_team_invitation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
    ) -> Result<()>;

    /// Accepts an exact non-ticketed organizer admission offer.
    async fn accept_event_admission_offer(
        &self,
        actor_user_id: Uuid,
        admission_offer_id: Uuid,
        registration_answers: Option<QuestionnaireAnswers>,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<AcceptEventAdmissionOfferResult>;

    /// Accepts a pending group team invitation.
    async fn accept_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid)
    -> Result<()>;

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

    /// Declines an active admission offer owned by the user.
    async fn decline_event_admission_offer(
        &self,
        actor_user_id: Uuid,
        admission_offer_id: Uuid,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<EventEnrollmentReconciliationOutcome>;

    /// Deletes a session proposal for the user.
    async fn delete_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()>;

    /// Gets the co-speaker user id for one of the user's session proposals.
    async fn get_session_proposal_co_speaker_user_id(
        &self,
        user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<Option<SessionProposalCoSpeakerUser>>;

    /// Gets one active badge owned by the user.
    async fn get_user_badge(&self, user_id: Uuid, user_badge_id: Uuid)
    -> Result<Option<UserBadge>>;

    /// Lists all available session proposal levels.
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>>;

    /// Lists user dashboard audit log rows.
    async fn list_user_audit_logs(
        &self,
        actor_user_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput>;

    /// Lists active badges owned by the user.
    async fn list_user_badges(&self, user_id: Uuid) -> Result<Vec<UserBadge>>;

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

    /// Lists groups where the user is a member or accepted team member.
    async fn list_user_dashboard_groups(
        &self,
        user_id: Uuid,
        filters: &UserGroupsFilters,
    ) -> Result<UserGroupsOutput>;

    /// Lists active event admission offers owned by the user.
    async fn list_user_event_invitations(&self, user_id: Uuid) -> Result<Vec<EventInvitation>>;

    /// Lists upcoming events where the user participates.
    async fn list_user_events(
        &self,
        user_id: Uuid,
        filters: &UserEventsFilters,
    ) -> Result<UserEventsOutput>;

    /// Lists all pending group team invitations for the user.
    async fn list_user_group_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<GroupTeamInvitation>>;

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

    /// Ensures an active badge owned by the user carries a current email identity binding.
    async fn refresh_user_badge_identity(
        &self,
        user_id: Uuid,
        user_badge_id: Uuid,
    ) -> Result<UserBadgeIdentity>;

    /// Rejects a pending community team invitation.
    async fn reject_community_team_invitation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
    ) -> Result<()>;

    /// Rejects a pending group team invitation.
    async fn reject_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid)
    -> Result<()>;

    /// Rejects a pending co-speaker invitation for a session proposal.
    async fn reject_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()>;

    /// Resubmits a CFS submission for the user.
    async fn resubmit_cfs_submission(
        &self,
        actor_user_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<()>;

    /// Permanently revokes a badge owned by the user.
    async fn revoke_user_badge(&self, actor_user_id: Uuid, user_badge_id: Uuid) -> Result<()>;

    /// Submits registration question answers for a user's event and returns whether it became confirmed.
    async fn submit_event_registration_answers(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_id: Uuid,
        registration_answers: &QuestionnaireAnswers,
    ) -> Result<bool>;

    /// Updates a session proposal for the user.
    async fn update_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<()>;

    /// Updates whether an active badge is discoverable on profiles.
    async fn update_user_badge_listing(
        &self,
        actor_user_id: Uuid,
        user_badge_id: Uuid,
        is_listed: bool,
    ) -> Result<()>;

    /// Reorders every active badge owned by the user.
    async fn update_user_badges_order(
        &self,
        actor_user_id: Uuid,
        user_badge_ids: &[Uuid],
    ) -> Result<()>;

    /// Withdraws a CFS submission for the user.
    async fn withdraw_cfs_submission(
        &self,
        actor_user_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBDashboardUser for T
where
    T: PgExecutor + Send + Sync,
{
    /// [`DBDashboardUser::accept_community_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_community_team_invitation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select accept_community_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &community_id],
        )
        .await
    }

    /// [`DBDashboardUser::accept_event_admission_offer`].
    #[instrument(skip(self, registration_answers), err)]
    async fn accept_event_admission_offer(
        &self,
        actor_user_id: Uuid,
        admission_offer_id: Uuid,
        registration_answers: Option<QuestionnaireAnswers>,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<AcceptEventAdmissionOfferResult> {
        let output: AcceptEventAdmissionOfferOutput = self
            .fetch_json_one(
                "
                select accept_event_admission_offer(
                    $1::uuid,
                    $2::uuid,
                    $3::jsonb,
                    $4::text
                )
                ",
                &[
                    &actor_user_id,
                    &admission_offer_id,
                    &registration_answers.as_ref().map(Json),
                    &payment_provider.map(|provider| provider.to_string()),
                ],
            )
            .await?;

        Ok(output.into())
    }

    /// [`DBDashboardUser::accept_group_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_group_team_invitation(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
    ) -> Result<()> {
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

    /// [`DBDashboardUser::decline_event_admission_offer`].
    #[instrument(skip(self), err)]
    async fn decline_event_admission_offer(
        &self,
        actor_user_id: Uuid,
        admission_offer_id: Uuid,
        payment_provider: Option<PaymentProvider>,
    ) -> Result<EventEnrollmentReconciliationOutcome> {
        self.fetch_json_one(
            "
            select decline_event_admission_offer(
                $1::uuid,
                $2::uuid,
                $3::text
            )
            ",
            &[
                &actor_user_id,
                &admission_offer_id,
                &payment_provider.map(|provider| provider.to_string()),
            ],
        )
        .await
    }

    /// [`DBDashboardUser::delete_session_proposal`]
    #[instrument(skip(self), err)]
    async fn delete_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()> {
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
        let db = self.client().await?;
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

    /// [`DBDashboardUser::get_user_badge`].
    #[instrument(skip(self), err)]
    async fn get_user_badge(
        &self,
        user_id: Uuid,
        user_badge_id: Uuid,
    ) -> Result<Option<UserBadge>> {
        self.fetch_json_opt(
            "select get_user_badge($1::uuid, $2::uuid)",
            &[&user_id, &user_badge_id],
        )
        .await
    }

    /// [`DBDashboardUser::list_session_proposal_levels`]
    #[instrument(skip(self), err)]
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>> {
        self.fetch_json_one("select list_session_proposal_levels()", &[])
            .await
    }

    /// [`DBDashboardUser::list_user_audit_logs`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_audit_logs(
        &self,
        actor_user_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput> {
        self.fetch_json_one(
            "select list_user_audit_logs($1::uuid, $2::jsonb)",
            &[&actor_user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_badges`].
    #[instrument(skip(self), err)]
    async fn list_user_badges(&self, user_id: Uuid) -> Result<Vec<UserBadge>> {
        self.fetch_json_one("select list_user_badges($1::uuid)", &[&user_id])
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

    /// [`DBDashboardUser::list_user_dashboard_groups`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_dashboard_groups(
        &self,
        user_id: Uuid,
        filters: &UserGroupsFilters,
    ) -> Result<UserGroupsOutput> {
        self.fetch_json_one(
            "select list_user_dashboard_groups($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_event_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_event_invitations(&self, user_id: Uuid) -> Result<Vec<EventInvitation>> {
        self.fetch_json_one("select list_user_event_invitations($1::uuid)", &[&user_id])
            .await
    }

    /// [`DBDashboardUser::list_user_events`]
    #[instrument(skip(self, filters), err)]
    async fn list_user_events(
        &self,
        user_id: Uuid,
        filters: &UserEventsFilters,
    ) -> Result<UserEventsOutput> {
        self.fetch_json_one(
            "select list_user_events($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_group_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_group_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<GroupTeamInvitation>> {
        self.fetch_json_one(
            "select list_user_group_team_invitations($1::uuid)",
            &[&user_id],
        )
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

    /// [`DBDashboardUser::refresh_user_badge_identity`].
    #[instrument(skip(self), err)]
    async fn refresh_user_badge_identity(
        &self,
        user_id: Uuid,
        user_badge_id: Uuid,
    ) -> Result<UserBadgeIdentity> {
        self.fetch_json_one(
            "select refresh_user_badge_identity($1::uuid, $2::uuid)",
            &[&user_id, &user_badge_id],
        )
        .await
    }

    /// [`DBDashboardUser::reject_community_team_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_community_team_invitation(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select reject_community_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &community_id],
        )
        .await
    }

    /// [`DBDashboardUser::reject_group_team_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_group_team_invitation(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
    ) -> Result<()> {
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
    async fn resubmit_cfs_submission(
        &self,
        actor_user_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select resubmit_cfs_submission($1::uuid, $2::uuid)",
            &[&actor_user_id, &cfs_submission_id],
        )
        .await
    }

    /// [`DBDashboardUser::revoke_user_badge`].
    #[instrument(skip(self), err)]
    async fn revoke_user_badge(&self, actor_user_id: Uuid, user_badge_id: Uuid) -> Result<()> {
        self.execute(
            "select revoke_user_badge($1::uuid, $2::uuid)",
            &[&actor_user_id, &user_badge_id],
        )
        .await
    }

    /// [`DBDashboardUser::submit_event_registration_answers`]
    #[instrument(skip(self, registration_answers), err)]
    async fn submit_event_registration_answers(
        &self,
        actor_user_id: Uuid,
        community_id: Uuid,
        event_id: Uuid,
        registration_answers: &QuestionnaireAnswers,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select submit_event_registration_answers($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &community_id,
                &event_id,
                &Json(registration_answers),
            ],
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
            &[
                &actor_user_id,
                &session_proposal_id,
                &Json(session_proposal),
            ],
        )
        .await
    }

    /// [`DBDashboardUser::update_user_badge_listing`].
    #[instrument(skip(self), err)]
    async fn update_user_badge_listing(
        &self,
        actor_user_id: Uuid,
        user_badge_id: Uuid,
        is_listed: bool,
    ) -> Result<()> {
        self.execute(
            "select update_user_badge_listing($1::uuid, $2::uuid, $3::boolean)",
            &[&actor_user_id, &user_badge_id, &is_listed],
        )
        .await
    }

    /// [`DBDashboardUser::update_user_badges_order`].
    #[instrument(skip(self, user_badge_ids), err)]
    async fn update_user_badges_order(
        &self,
        actor_user_id: Uuid,
        user_badge_ids: &[Uuid],
    ) -> Result<()> {
        self.execute(
            "select update_user_badges_order($1::uuid, $2::uuid[])",
            &[&actor_user_id, &user_badge_ids],
        )
        .await
    }

    /// [`DBDashboardUser::withdraw_cfs_submission`]
    #[instrument(skip(self), err)]
    async fn withdraw_cfs_submission(
        &self,
        actor_user_id: Uuid,
        cfs_submission_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select withdraw_cfs_submission($1::uuid, $2::uuid)",
            &[&actor_user_id, &cfs_submission_id],
        )
        .await
    }
}

/// Scope returned after accepting an exact event admission offer.
#[derive(Debug, Clone, Copy, Deserialize)]
pub(crate) struct AcceptedEventAdmissionOffer {
    /// Community containing the accepted offer's event.
    pub community_id: Uuid,
    /// Event associated with the accepted offer.
    pub event_id: Uuid,
}

/// Conflict returned while accepting an event admission offer.
#[derive(Debug, Clone, Copy, Eq, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum AcceptEventAdmissionOfferConflict {
    /// The selected admission offer is no longer claimable.
    AdmissionOfferUnavailable,
}

/// Result of accepting an event admission offer.
#[derive(Debug, Clone, Copy)]
pub(crate) enum AcceptEventAdmissionOfferResult {
    /// The offer was accepted.
    Accepted(AcceptedEventAdmissionOffer),
    /// The offer could not be accepted.
    Conflict(AcceptEventAdmissionOfferConflict),
}

impl From<AcceptEventAdmissionOfferOutput> for AcceptEventAdmissionOfferResult {
    /// Converts database offer acceptance output into the caller-facing result.
    fn from(output: AcceptEventAdmissionOfferOutput) -> Self {
        match output {
            AcceptEventAdmissionOfferOutput::Accepted(accepted) => Self::Accepted(accepted),
            AcceptEventAdmissionOfferOutput::Conflict { conflict } => Self::Conflict(conflict),
        }
    }
}

/// Co-speaker identifier for a session proposal.
#[derive(Debug, Clone)]
pub(crate) struct SessionProposalCoSpeakerUser {
    /// Optional co-speaker user identifier.
    pub co_speaker_user_id: Option<Uuid>,
}

/// Database output returned after accepting an event admission offer.
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum AcceptEventAdmissionOfferOutput {
    /// The offer was accepted.
    Accepted(AcceptedEventAdmissionOffer),
    /// The offer could not be accepted.
    Conflict {
        /// Conflict kind.
        conflict: AcceptEventAdmissionOfferConflict,
    },
}
