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
        MockInterviewMatchInput, MockInterviewRequestInput,
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

    /// Submit a mock interview request.
    async fn add_mock_interview_request(
        &self,
        user_id: Uuid,
        input: &MockInterviewRequestInput,
    ) -> Result<Uuid>;

    /// Create or update a match and schedule.
    async fn upsert_mock_interview_match(
        &self,
        actor_user_id: Uuid,
        request_id: Uuid,
        input: &MockInterviewMatchInput,
    ) -> Result<Uuid>;

    /// Record feedback and final status.
    async fn update_mock_interview_feedback(
        &self,
        actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewFeedbackInput,
    ) -> Result<()>;
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
            )
            select jsonb_build_object(
                'requests', request_rows.requests,
                'matches', match_rows.matches,
                'stats', stat_rows.stats,
                'total', (
                    select count(*)::int
                    from mock_interview_request mir
                    where ($1::text is null or mir.status = $1::text)
                )
            )
            from request_rows, match_rows, stat_rows
            "#,
            &[
                &filters.status,
                &(filters.limit.unwrap_or(25) as i32),
                &(filters.offset.unwrap_or(0) as i32),
            ],
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
            r#"
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
            "#,
            &[&user_id, &Json(input)],
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
            r#"
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
                    scheduled_at = excluded.scheduled_at,
                    meeting_url = excluded.meeting_url,
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
            "#,
            &[&request_id, &actor_user_id, &Json(input)],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_mock_interview_feedback(
        &self,
        _actor_user_id: Uuid,
        match_id: Uuid,
        input: &MockInterviewFeedbackInput,
    ) -> Result<()> {
        self.execute(
            r#"
            with updated_match as (
                update mock_interview_match
                set status = $2::jsonb ->> 'status',
                    interviewer_feedback = $2::jsonb ->> 'interviewer_feedback',
                    interviewee_feedback = $2::jsonb ->> 'interviewee_feedback',
                    updated_at = current_timestamp
                where mock_interview_match_id = $1::uuid
                returning mock_interview_request_id, status
            )
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
            "#,
            &[&match_id, &Json(input)],
        )
        .await?;
        Ok(())
    }
}
