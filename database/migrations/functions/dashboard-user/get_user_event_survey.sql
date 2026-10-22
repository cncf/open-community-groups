-- Returns a survey the user reaches from the dashboard: the survey, its state,
-- the event summary and the user's response. Open surveys are returned to the
-- users in their audience, so they can answer them, and closed surveys to the
-- users who answered them, so they can review their answers. Null for any
-- other survey or for surveys attendees cannot reach on the public site.
create or replace function get_user_event_survey(
    p_event_survey_id uuid,
    p_user_id uuid
)
returns json as $$
    select json_build_object(
        'anonymous', s.anonymous,
        'event', get_event_summary(c.community_id, g.group_id, e.event_id),
        'event_survey_id', s.event_survey_id,
        'questions', s.questions,
        'revision', s.revision,
        'state', us.state,
        'title', s.title,

        'closed_at', epoch_seconds(us.closed_at),
        'closes_at', epoch_seconds(s.closes_at),
        'description', s.description,
        'response', (
            select json_build_object(
                'answers', r.answers,
                'created_at', epoch_seconds(r.created_at),

                'updated_at', epoch_seconds(r.updated_at)
            )
            from event_survey_response r
            where r.event_survey_id = s.event_survey_id
            and r.user_id = p_user_id
        )
    )
    from user_dashboard_event_surveys(p_user_id) us
    join event_survey s on s.event_survey_id = us.event_survey_id
    join event e on e.event_id = s.event_id
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    where us.event_survey_id = p_event_survey_id;
$$ language sql;
