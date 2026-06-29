//! Database interface for user dashboard operations.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    templates::dashboard::{
        audit::{AuditLogFilters, AuditLogsOutput},
        user::{
            coffee_meet::{CoffeeMeetSubscription, CoffeeMeetSubscriptionForm},
            events::{UserEventsFilters, UserEventsOutput},
            invitations::{AllianceTeamInvitation, EventInvitation, GroupTeamInvitation},
            mentorship::{ListPage as MentorshipRequestsOutput, MentorshipRequest},
            session_proposals::{
                PendingCoSpeakerInvitation, SessionProposalInput, SessionProposalLevel,
                SessionProposalsFilters, SessionProposalsOutput,
            },
            submissions::{CfsSubmissionsFilters, CfsSubmissionsOutput},
        },
    },
    types::questionnaire::QuestionnaireAnswers,
};

/// Database trait for user dashboard operations.
#[async_trait]
pub(crate) trait DBDashboardUser {
    /// Accepts a pending alliance team invitation.
    async fn accept_alliance_team_invitation(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
    ) -> Result<()>;

    /// Accepts a pending organizer-created event invitation.
    async fn accept_event_attendee_invitation(
        &self,
        actor_user_id: Uuid,
        event_id: Uuid,
    ) -> Result<Uuid>;

    /// Accepts a pending group team invitation.
    async fn accept_group_team_invitation(&self, actor_user_id: Uuid, group_id: Uuid)
    -> Result<()>;

    /// Accepts a pending co-speaker invitation for a session proposal.
    async fn accept_session_proposal_co_speaker_invitation(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
    ) -> Result<()>;

    /// Counts pending dashboard invitations the user can act on.
    async fn count_user_pending_invitations(&self, user_id: Uuid) -> Result<i64>;

    /// Adds a new session proposal for the user.
    async fn add_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal: &SessionProposalInput,
    ) -> Result<Uuid>;

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

    /// Lists all available session proposal levels.
    async fn list_session_proposal_levels(&self) -> Result<Vec<SessionProposalLevel>>;

    /// Lists user dashboard audit log rows.
    async fn list_user_audit_logs(
        &self,
        actor_user_id: Uuid,
        filters: &AuditLogFilters,
    ) -> Result<AuditLogsOutput>;

    /// Lists all CFS submissions for the user.
    async fn list_user_cfs_submissions(
        &self,
        user_id: Uuid,
        filters: &CfsSubmissionsFilters,
    ) -> Result<CfsSubmissionsOutput>;

    /// Lists all pending alliance team invitations for the user.
    async fn list_user_alliance_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<AllianceTeamInvitation>>;

    /// Lists all pending organizer-created event invitations for the user.
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

    /// Lists `CoffeeMeet` subscriptions available to a user.
    async fn list_user_coffee_meet_subscriptions(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CoffeeMeetSubscription>>;

    /// Lists mentorship requests received by the user.
    async fn list_user_mentorship_requests(
        &self,
        user_id: Uuid,
    ) -> Result<MentorshipRequestsOutput>;

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

    /// Rejects a pending alliance team invitation.
    async fn reject_alliance_team_invitation(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
    ) -> Result<()>;

    /// Rejects a pending organizer-created event invitation.
    async fn reject_event_attendee_invitation(
        &self,
        actor_user_id: Uuid,
        event_id: Uuid,
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

    /// Submits registration question answers for a user's event and returns whether it became confirmed.
    async fn submit_event_registration_answers(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_id: Uuid,
        registration_answers: &QuestionnaireAnswers,
    ) -> Result<bool>;

    /// Subscribes or updates a `CoffeeMeet` cadence.
    async fn upsert_coffee_meet_subscription(
        &self,
        actor_user_id: Uuid,
        subscription: &CoffeeMeetSubscriptionForm,
    ) -> Result<()>;

    /// Unsubscribes from `CoffeeMeet` for a group.
    async fn unsubscribe_coffee_meet(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()>;

    /// Updates a session proposal for the user.
    async fn update_session_proposal(
        &self,
        actor_user_id: Uuid,
        session_proposal_id: Uuid,
        session_proposal: &SessionProposalInput,
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
    /// [`DBDashboardUser::accept_alliance_team_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_alliance_team_invitation(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select accept_alliance_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &alliance_id],
        )
        .await
    }

    /// [`DBDashboardUser::accept_event_attendee_invitation`]
    #[instrument(skip(self), err)]
    async fn accept_event_attendee_invitation(
        &self,
        actor_user_id: Uuid,
        event_id: Uuid,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            "select accept_event_attendee_invitation($1::uuid, $2::uuid)::uuid",
            &[&actor_user_id, &event_id],
        )
        .await
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

    /// [`DBDashboardUser::count_user_pending_invitations`]
    #[instrument(skip(self), err)]
    async fn count_user_pending_invitations(&self, user_id: Uuid) -> Result<i64> {
        self.fetch_scalar_one(
            "select count_user_pending_invitations($1::uuid)::bigint",
            &[&user_id],
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

    /// [`DBDashboardUser::list_user_alliance_team_invitations`]
    #[instrument(skip(self), err)]
    async fn list_user_alliance_team_invitations(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<AllianceTeamInvitation>> {
        self.fetch_json_one(
            "select list_user_alliance_team_invitations($1::uuid)",
            &[&user_id],
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

    /// [`DBDashboardUser::list_user_coffee_meet_subscriptions`]
    #[instrument(skip(self), err)]
    async fn list_user_coffee_meet_subscriptions(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CoffeeMeetSubscription>> {
        self.fetch_json_one(
            "select list_user_coffee_meet_subscriptions($1::uuid)",
            &[&user_id],
        )
        .await
    }

    /// [`DBDashboardUser::list_user_mentorship_requests`]
    #[instrument(skip(self), err)]
    async fn list_user_mentorship_requests(
        &self,
        user_id: Uuid,
    ) -> Result<MentorshipRequestsOutput> {
        let db = self.client().await?;
        let rows = db
            .query(
                "
                select
                    mr.mentorship_request_id,
                    mr.requester_user_id,
                    requester.email as requester_email,
                    requester.username as requester_username,
                    requester.name as requester_name,
                    requester.company as requester_company,
                    requester.title as requester_title,
                    requester.photo_url as requester_photo_url,
                    mr.audience_type,
                    mr.message,
                    mr.created_at,
                    count(*) over()::bigint as total
                from mentorship_request mr
                join \"user\" requester on requester.user_id = mr.requester_user_id
                where mr.mentor_user_id = $1::uuid
                order by mr.created_at desc
                limit 100;
                ",
                &[&user_id],
            )
            .await?;

        let total = rows.first().map_or(0, |row| row.get("total"));
        let requests = rows
            .into_iter()
            .map(|row| MentorshipRequest {
                mentorship_request_id: row.get("mentorship_request_id"),
                requester_user_id: row.get("requester_user_id"),
                requester_email: row.get("requester_email"),
                requester_username: row.get("requester_username"),
                requester_name: row.get("requester_name"),
                requester_company: row.get("requester_company"),
                requester_title: row.get("requester_title"),
                requester_photo_url: row.get("requester_photo_url"),
                audience_type: row.get("audience_type"),
                message: row.get("message"),
                created_at: row.get("created_at"),
            })
            .collect();

        Ok(MentorshipRequestsOutput { total, requests })
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

    /// [`DBDashboardUser::reject_alliance_team_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_alliance_team_invitation(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select reject_alliance_team_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &alliance_id],
        )
        .await
    }

    /// [`DBDashboardUser::reject_event_attendee_invitation`]
    #[instrument(skip(self), err)]
    async fn reject_event_attendee_invitation(
        &self,
        actor_user_id: Uuid,
        event_id: Uuid,
    ) -> Result<()> {
        self.execute(
            "select reject_event_attendee_invitation($1::uuid, $2::uuid)",
            &[&actor_user_id, &event_id],
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

    /// [`DBDashboardUser::submit_event_registration_answers`]
    #[instrument(skip(self, registration_answers), err)]
    async fn submit_event_registration_answers(
        &self,
        actor_user_id: Uuid,
        alliance_id: Uuid,
        event_id: Uuid,
        registration_answers: &QuestionnaireAnswers,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            "select submit_event_registration_answers($1::uuid, $2::uuid, $3::uuid, $4::jsonb)",
            &[
                &actor_user_id,
                &alliance_id,
                &event_id,
                &Json(registration_answers),
            ],
        )
        .await
    }

    /// [`DBDashboardUser::upsert_coffee_meet_subscription`]
    #[instrument(skip(self, subscription), err)]
    async fn upsert_coffee_meet_subscription(
        &self,
        actor_user_id: Uuid,
        subscription: &CoffeeMeetSubscriptionForm,
    ) -> Result<()> {
        self.execute(
            "select upsert_coffee_meet_subscription($1::uuid, $2::uuid, $3::text)",
            &[
                &actor_user_id,
                &subscription.group_id,
                &subscription.frequency,
            ],
        )
        .await
    }

    /// [`DBDashboardUser::unsubscribe_coffee_meet`]
    #[instrument(skip(self), err)]
    async fn unsubscribe_coffee_meet(&self, actor_user_id: Uuid, group_id: Uuid) -> Result<()> {
        self.execute(
            "select unsubscribe_coffee_meet($1::uuid, $2::uuid)",
            &[&actor_user_id, &group_id],
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

/// Co-speaker identifier for a session proposal.
#[derive(Debug, Clone)]
pub(crate) struct SessionProposalCoSpeakerUser {
    pub co_speaker_user_id: Option<Uuid>,
}
