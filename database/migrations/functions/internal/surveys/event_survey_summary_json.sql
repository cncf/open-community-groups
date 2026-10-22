-- Returns the summary projection of a survey shared by the dashboard readers.
-- Timestamps are encoded with epoch_seconds. Counts, state and opening time
-- are computed live: eligible counts follow the survey audience, eligible
-- respondents are current eligible users with a response, and the survey is
-- locked once it has received a response. responses_count counts every stored
-- response, including those of users who are no longer eligible. The
-- anonymity of anonymous surveys is locked once they have opened or their
-- opening email was processed.
create or replace function event_survey_summary_json(
    p_event_survey event_survey,
    p_event event
)
returns jsonb as $$
    with eligible as (
        select eu.user_id
        from event_survey_eligible_users(p_event.event_id, p_event_survey.audience) eu
    )
    select jsonb_build_object(
        'anonymous', p_event_survey.anonymous,
        'audience', p_event_survey.audience,
        'event_survey_id', p_event_survey.event_survey_id,
        'revision', p_event_survey.revision,
        'title', p_event_survey.title,

        'closes_at', epoch_seconds(p_event_survey.closes_at),
        'open_notification_processed_at', epoch_seconds(p_event_survey.open_notification_processed_at),

        'anonymous_locked', p_event_survey.anonymous and (
            p_event_survey.open_notification_processed_at is not null
            or event_survey_state(p_event_survey, p_event) in ('closed', 'open')
        ),
        'closed_manually', p_event_survey.closed_at is not null,
        'effective_opens_at', epoch_seconds(event_survey_effective_opens_at(p_event_survey, p_event)),
        'eligible_count', (select count(*) from eligible),
        'eligible_respondents_count', (
            select count(*)
            from eligible e
            join event_survey_response r on r.user_id = e.user_id
            where r.event_survey_id = p_event_survey.event_survey_id
        ),
        'locked', p_event_survey.first_response_at is not null,
        'questions_count', jsonb_array_length(p_event_survey.questions),
        'responses_count', (
            select count(*)
            from event_survey_response r
            where r.event_survey_id = p_event_survey.event_survey_id
        ),
        'state', event_survey_state(p_event_survey, p_event)
    );
$$ language sql stable;
