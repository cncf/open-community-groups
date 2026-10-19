-- Returns the survey a user answers from the dashboard: the survey, the event
-- summary and the user's response. Null unless the survey is reachable on the
-- public site, open, and the user is in its audience.
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
        'title', s.title,

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
    from event_survey s
    join event e on e.event_id = s.event_id
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    where s.event_survey_id = p_event_survey_id
    and is_event_survey_public(s, e, g, c)
    and event_survey_state(s, e) = 'open'
    and exists (
        select 1
        from event_survey_eligible_users(e.event_id, s.audience) eu
        where eu.user_id = p_user_id
    );
$$ language sql;
