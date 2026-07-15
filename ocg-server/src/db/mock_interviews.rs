//! Database operations for mock interviews.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    types::mock_interviews::{
        MockInterviewDashboard, MockInterviewFeedbackInput, MockInterviewFilters,
        MockInterviewMatchInput, MockInterviewMatchNotificationContext,
        MockInterviewParticipantFeedbackInput, MockInterviewParticipantScheduleInput,
        MockInterviewRequest, MockInterviewRequestInput, UserMockInterviewMatch,
    },
};

/// Database operations for the mock interview product area.
#[async_trait]
pub(crate) trait DBMockInterviews {
    /// List the dashboard queue and matches.
    async fn get_mock_interview_dashboard(
        &self,
        filters: &MockInterviewFilters,
    ) -> Result<MockInterviewDashboard>;

    /// List matches where the user is an assigned participant.
    async fn list_user_mock_interview_matches(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<UserMockInterviewMatch>>;

    /// List requests submitted by the user.
    async fn list_user_mock_interview_requests(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<MockInterviewRequest>>;

    /// Submit a mock interview request.
    async fn add_mock_interview_request(
        &self,
        user_id: Uuid,
        input: &MockInterviewRequestInput,
    ) -> Result<Uuid>;

    /// Request a group member as the interviewer's match.
    async fn request_group_mock_interviewer(
        &self,
        requester_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        interviewer_user_id: Uuid,
    ) -> Result<Option<Uuid>>;

    /// Create or update a match.
    async fn upsert_mock_interview_match(
        &self,
        actor_user_id: Uuid,
        request_id: Uuid,
        input: &MockInterviewMatchInput,
    ) -> Result<Uuid>;

    /// Fetch participant context for match notifications.
    async fn get_mock_interview_match_notification_context(
        &self,
        match_id: Uuid,
    ) -> Result<Option<MockInterviewMatchNotificationContext>>;

    /// Record feedback and final status.
    async fn update_mock_interview_feedback(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewFeedbackInput,
    ) -> Result<bool>;

    /// Record feedback for the actor's assigned role in a match.
    async fn update_user_mock_interview_feedback(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewParticipantFeedbackInput,
    ) -> Result<bool>;

    /// Schedule an assigned match as one of its participants.
    async fn update_user_mock_interview_schedule(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewParticipantScheduleInput,
    ) -> Result<bool>;
}

#[async_trait]
impl<T> DBMockInterviews for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self, filters), err)]
    async fn get_mock_interview_dashboard(
        &self,
        filters: &MockInterviewFilters,
    ) -> Result<MockInterviewDashboard> {
        let limit = i32::try_from(filters.limit.unwrap_or(25))?;
        let offset = i32::try_from(filters.offset.unwrap_or(0))?;

        self.fetch_json_one(
            r#"
            with filtered_requests as (
                select mir.*, u.username, u.email, u.name
                from mock_interview_request mir
                join "user" u on u.user_id = mir.requester_user_id
                where ($1::text is null or mir.status = $1::text)
                order by mir.created_at desc
                limit $2::int
                offset $3::int
            ),
            request_rows as (
                select coalesce(jsonb_agg(jsonb_build_object(
                    'mock_interview_request_id', fr.mock_interview_request_id,
                    'requester_user_id', fr.requester_user_id,
                    'requester_username', fr.username,
                    'requester_name', fr.name,
                    'requester_email', fr.email,
                    'practice_role', fr.practice_role,
                    'interview_type', fr.interview_type,
                    'target_company', fr.target_company,
                    'seniority', fr.seniority,
                    'location', fr.location,
                    'availability', fr.availability,
                    'notes', fr.notes,
                    'status', fr.status,
                    'created_at', extract(epoch from fr.created_at)::bigint,
                    'updated_at', extract(epoch from fr.updated_at)::bigint
                ) order by fr.created_at desc), '[]'::jsonb) as requests
                from filtered_requests fr
            ),
            match_rows as (
                select coalesce(jsonb_agg(jsonb_build_object(
                    'mock_interview_match_id', mim.mock_interview_match_id,
                    'mock_interview_request_id', mim.mock_interview_request_id,
                    'interviewer_user_id', mim.interviewer_user_id,
                    'interviewer_label', coalesce(interviewer.name, interviewer.username),
                    'interviewee_user_id', mim.interviewee_user_id,
                    'interviewee_label', coalesce(interviewee.name, interviewee.username),
                    'scheduled_at', to_char(mim.scheduled_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'),
                    'meeting_url', mim.meeting_url,
                    'status', mim.status,
                    'internal_notes', mim.internal_notes,
                    'interviewer_feedback', mim.interviewer_feedback,
                    'interviewee_feedback', mim.interviewee_feedback,
                    'interviewer_rating', mim.interviewer_rating,
                    'created_at', extract(epoch from mim.created_at)::bigint
                ) order by mim.scheduled_at desc nulls last, mim.created_at desc), '[]'::jsonb) as matches
                from mock_interview_match mim
                left join "user" interviewer on interviewer.user_id = mim.interviewer_user_id
                left join "user" interviewee on interviewee.user_id = mim.interviewee_user_id
            ),
            stat_rows as (
                select coalesce(jsonb_agg(jsonb_build_object(
                    'dimension', dimension,
                    'value', value,
                    'count', count
                ) order by dimension, count desc), '[]'::jsonb) as stats
                from (
                    select 'interview_type' as dimension, interview_type as value, count(*)::bigint as count
                    from mock_interview_request
                    group by interview_type
                    union all
                    select 'target_company' as dimension, target_company as value, count(*)::bigint as count
                    from mock_interview_request
                    group by target_company
                    union all
                    select 'location' as dimension, location as value, count(*)::bigint as count
                    from mock_interview_request
                    group by location
                ) stats
            ),
            metric_rows as (
                select jsonb_build_object(
                    'total_requests', (
                        select count(*)::int
                        from mock_interview_request
                    ),
                    'pending_requests', (
                        select count(*)::int
                        from mock_interview_request
                        where status = 'requested'
                    ),
                    'active_requests', (
                        select count(*)::int
                        from mock_interview_request
                        where status in ('matched', 'scheduled')
                    ),
                    'total_matches', (
                        select count(*)::int
                        from mock_interview_match
                    ),
                    'active_matches', (
                        select count(*)::int
                        from mock_interview_match
                        where status in ('matched', 'scheduled')
                    ),
                    'completed_matches', (
                        select count(*)::int
                        from mock_interview_match
                        where status = 'completed'
                    ),
                    'canceled_matches', (
                        select count(*)::int
                        from mock_interview_match
                        where status = 'canceled'
                    ),
                    'feedback_count', (
                        select count(*)::int
                        from mock_interview_match
                        where interviewer_feedback is not null
                        or interviewee_feedback is not null
                        or interviewer_rating is not null
                    ),
                    'average_interviewer_rating', (
                        select round(avg(interviewer_rating)::numeric, 1)::float8
                        from mock_interview_match
                        where interviewer_rating is not null
                    )
                ) as metrics
            )
            select jsonb_build_object(
                'requests', request_rows.requests,
                'matches', match_rows.matches,
                'stats', stat_rows.stats,
                'metrics', metric_rows.metrics,
                'total', (
                    select count(*)::int
                    from mock_interview_request mir
                    where ($1::text is null or mir.status = $1::text)
                )
            )
            from request_rows, match_rows, stat_rows, metric_rows
            "#,
            &[
                &filters.status,
                &limit,
                &offset,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn list_user_mock_interview_matches(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<UserMockInterviewMatch>> {
        self.fetch_json_one(
            r#"
            select coalesce(jsonb_agg(jsonb_build_object(
                'mock_interview_match_id', mim.mock_interview_match_id,
                'mock_interview_request_id', mim.mock_interview_request_id,
                'interviewer_user_id', mim.interviewer_user_id,
                'interviewer_label', coalesce(interviewer.name, interviewer.username),
                'interviewee_user_id', mim.interviewee_user_id,
                'interviewee_label', coalesce(interviewee.name, interviewee.username),
                'scheduled_at', to_char(mim.scheduled_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'),
                'meeting_url', mim.meeting_url,
                'status', mim.status,
                'internal_notes', mim.internal_notes,
                'interviewer_feedback', mim.interviewer_feedback,
                'interviewee_feedback', mim.interviewee_feedback,
                'interviewer_rating', mim.interviewer_rating,
                'created_at', extract(epoch from mim.created_at)::bigint,
                'role', case
                    when mim.interviewer_user_id = $1::uuid then 'interviewer'
                    else 'interviewee'
                end
            ) order by mim.scheduled_at desc nulls last, mim.created_at desc), '[]'::jsonb)
            from mock_interview_match mim
            left join "user" interviewer on interviewer.user_id = mim.interviewer_user_id
            left join "user" interviewee on interviewee.user_id = mim.interviewee_user_id
            where mim.interviewer_user_id = $1::uuid
            or mim.interviewee_user_id = $1::uuid
            "#,
            &[&user_id],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn list_user_mock_interview_requests(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<MockInterviewRequest>> {
        self.fetch_json_one(
            r#"
            select coalesce(jsonb_agg(jsonb_build_object(
                'mock_interview_request_id', mir.mock_interview_request_id,
                'requester_user_id', mir.requester_user_id,
                'requester_username', u.username,
                'requester_name', u.name,
                'requester_email', u.email,
                'practice_role', mir.practice_role,
                'interview_type', mir.interview_type,
                'target_company', mir.target_company,
                'seniority', mir.seniority,
                'location', mir.location,
                'availability', mir.availability,
                'notes', mir.notes,
                'status', mir.status,
                'created_at', extract(epoch from mir.created_at)::bigint,
                'updated_at', extract(epoch from mir.updated_at)::bigint
            ) order by mir.created_at desc), '[]'::jsonb)
            from mock_interview_request mir
            join "user" u on u.user_id = mir.requester_user_id
            where mir.requester_user_id = $1::uuid
            "#,
            &[&user_id],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_mock_interview_request(
        &self,
        user_id: Uuid,
        input: &MockInterviewRequestInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r"
            insert into mock_interview_request (
                requester_user_id,
                practice_role,
                interview_type,
                target_company,
                seniority,
                location,
                availability,
                notes
            )
            values (
                $1::uuid,
                $2::jsonb ->> 'practice_role',
                $2::jsonb ->> 'interview_type',
                $2::jsonb ->> 'target_company',
                $2::jsonb ->> 'seniority',
                $2::jsonb ->> 'location',
                $2::jsonb ->> 'availability',
                $2::jsonb ->> 'notes'
            )
            returning mock_interview_request_id
            ",
            &[&user_id, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn request_group_mock_interviewer(
        &self,
        requester_user_id: Uuid,
        alliance_id: Uuid,
        group_id: Uuid,
        interviewer_user_id: Uuid,
    ) -> Result<Option<Uuid>> {
        self.fetch_scalar_one(
            r#"
            with eligible_group as (
                select g.group_id
                from "group" g
                join alliance a on a.alliance_id = g.alliance_id
                where g.group_id = $3::uuid
                and g.alliance_id = $2::uuid
                and g.active = true
                and g.deleted = false
                and g.mock_interviews_enabled = true
                and a.mock_interviews_enabled = true
                and exists (
                    select 1
                    from group_member gm
                    where gm.group_id = g.group_id
                    and gm.user_id = $1::uuid
                )
                and exists (
                    select 1
                    from group_member gm
                    where gm.group_id = g.group_id
                    and gm.user_id = $4::uuid
                )
                and not exists (
                    select 1
                    from mock_interview_match mim
                    where mim.interviewee_user_id = $1::uuid
                    and mim.interviewer_user_id = $4::uuid
                    and mim.status <> 'canceled'
                )
            ),
            inserted_request as (
                insert into mock_interview_request (
                    requester_user_id,
                    practice_role,
                    interview_type,
                    target_company,
                    seniority,
                    location,
                    notes,
                    status
                )
                select
                    $1::uuid,
                    'interviewee',
                    'other',
                    'doesnt_matter',
                    'mid',
                    'other',
                    'Requested interviewer from member card.',
                    'matched'
                from eligible_group
                returning mock_interview_request_id
            ),
            inserted_match as (
                insert into mock_interview_match (
                    mock_interview_request_id,
                    created_by_user_id,
                    interviewer_user_id,
                    interviewee_user_id,
                    status,
                    internal_notes
                )
                select
                    mock_interview_request_id,
                    $1::uuid,
                    $4::uuid,
                    $1::uuid,
                    'matched',
                    'Requested from member card.'
                from inserted_request
                returning mock_interview_match_id
            )
            select (select mock_interview_match_id from inserted_match)
            "#,
            &[
                &requester_user_id,
                &alliance_id,
                &group_id,
                &interviewer_user_id,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn upsert_mock_interview_match(
        &self,
        actor_user_id: Uuid,
        request_id: Uuid,
        input: &MockInterviewMatchInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r"
            with upserted as (
                insert into mock_interview_match (
                    mock_interview_request_id,
                    created_by_user_id,
                    interviewer_user_id,
                    interviewee_user_id,
                    scheduled_at,
                    meeting_url,
                    status,
                    internal_notes
                )
                values (
                    $1::uuid,
                    $2::uuid,
                    nullif($3::jsonb ->> 'interviewer_user_id', '')::uuid,
                    nullif($3::jsonb ->> 'interviewee_user_id', '')::uuid,
                    nullif($3::jsonb ->> 'scheduled_at', '')::timestamptz,
                    $3::jsonb ->> 'meeting_url',
                    $3::jsonb ->> 'status',
                    $3::jsonb ->> 'internal_notes'
                )
                on conflict (mock_interview_request_id)
                do update set
                    interviewer_user_id = excluded.interviewer_user_id,
                    interviewee_user_id = excluded.interviewee_user_id,
                    scheduled_at = coalesce(excluded.scheduled_at, mock_interview_match.scheduled_at),
                    meeting_url = coalesce(excluded.meeting_url, mock_interview_match.meeting_url),
                    status = excluded.status,
                    internal_notes = excluded.internal_notes,
                    updated_at = current_timestamp
                returning mock_interview_match_id, status
            )
            update mock_interview_request mir
            set status = case
                    when upserted.status = 'scheduled' then 'scheduled'
                    when upserted.status = 'completed' then 'completed'
                    when upserted.status = 'canceled' then 'canceled'
                    else 'matched'
                end,
                updated_at = current_timestamp
            from upserted
            where mir.mock_interview_request_id = $1::uuid
            returning upserted.mock_interview_match_id
            ",
            &[&request_id, &actor_user_id, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn get_mock_interview_match_notification_context(
        &self,
        match_id: Uuid,
    ) -> Result<Option<MockInterviewMatchNotificationContext>> {
        self.fetch_json_opt(
            r#"
            select jsonb_build_object(
                'mock_interview_match_id', mim.mock_interview_match_id,
                'interviewer_user_id', mim.interviewer_user_id,
                'interviewer_username', interviewer.username,
                'interviewer_name', interviewer.name,
                'interviewee_user_id', mim.interviewee_user_id,
                'interviewee_username', interviewee.username,
                'interviewee_name', interviewee.name,
                'interview_type', mir.interview_type,
                'practice_role', mir.practice_role
            )
            from mock_interview_match mim
            join mock_interview_request mir
                on mir.mock_interview_request_id = mim.mock_interview_request_id
            left join "user" interviewer on interviewer.user_id = mim.interviewer_user_id
            left join "user" interviewee on interviewee.user_id = mim.interviewee_user_id
            where mim.mock_interview_match_id = $1::uuid
            "#,
            &[&match_id],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_mock_interview_feedback(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewFeedbackInput,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            r"
            with updated_match as (
                update mock_interview_match
                set status = $2::jsonb ->> 'status',
                    interviewer_feedback = $2::jsonb ->> 'interviewer_feedback',
                    interviewee_feedback = $2::jsonb ->> 'interviewee_feedback',
                    interviewer_rating = nullif($2::jsonb ->> 'interviewer_rating', '')::int,
                    updated_at = current_timestamp
                where mock_interview_match_id = $1::uuid
                and created_by_user_id = $3::uuid
                returning mock_interview_request_id, status
            ),
            updated_request as (
            update mock_interview_request mir
            set status = case
                    when updated_match.status = 'scheduled' then 'scheduled'
                    when updated_match.status = 'completed' then 'completed'
                    when updated_match.status = 'canceled' then 'canceled'
                    else 'matched'
                end,
                updated_at = current_timestamp
            from updated_match
            where mir.mock_interview_request_id = updated_match.mock_interview_request_id
                returning 1
            )
            select exists(select 1 from updated_request)
            ",
            &[&match_id, &Json(input), &actor_user_id],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_user_mock_interview_feedback(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewParticipantFeedbackInput,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            r"
            with updated_match as (
                update mock_interview_match
                set interviewer_feedback = case
                        when interviewer_user_id = $2::uuid then $3::jsonb ->> 'feedback'
                        else interviewer_feedback
                    end,
                    interviewee_feedback = case
                        when interviewee_user_id = $2::uuid then $3::jsonb ->> 'feedback'
                        else interviewee_feedback
                    end,
                    interviewer_rating = case
                        when interviewee_user_id = $2::uuid then nullif($3::jsonb ->> 'interviewer_rating', '')::int
                        else interviewer_rating
                    end,
                    updated_at = current_timestamp
                where mock_interview_match_id = $1::uuid
                and (interviewer_user_id = $2::uuid or interviewee_user_id = $2::uuid)
                returning 1
            )
            select exists(select 1 from updated_match)
            ",
            &[&match_id, &actor_user_id, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_user_mock_interview_schedule(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewParticipantScheduleInput,
    ) -> Result<bool> {
        self.fetch_scalar_one(
            r"
            with updated_match as (
                update mock_interview_match
                set scheduled_at = ($3::jsonb ->> 'scheduled_at')::timestamptz,
                    meeting_url = $3::jsonb ->> 'meeting_url',
                    status = case
                        when status in ('matched', 'scheduled') then 'scheduled'
                        else status
                    end,
                    updated_at = current_timestamp
                where mock_interview_match_id = $1::uuid
                and (interviewer_user_id = $2::uuid or interviewee_user_id = $2::uuid)
                returning mock_interview_request_id, status
            ),
            updated_request as (
                update mock_interview_request mir
                set status = case
                        when updated_match.status = 'scheduled' then 'scheduled'
                        when updated_match.status = 'completed' then 'completed'
                        when updated_match.status = 'canceled' then 'canceled'
                        else 'matched'
                    end,
                    updated_at = current_timestamp
                from updated_match
                where mir.mock_interview_request_id = updated_match.mock_interview_request_id
                returning 1
            )
            select exists(select 1 from updated_request)
            ",
            &[&match_id, &actor_user_id, &Json(input)],
        )
        .await
    }
}
