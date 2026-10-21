-- Returns the surveys a user reaches from the dashboard: open surveys of public
-- events whose audience includes the user, and closed surveys of public events
-- the user answered. Candidates come from the user's confirmed attendances and
-- responses, so the cost follows the user's own surveys. Each row tells whether
-- the user answered the survey, its state, and when a closed survey closed: the
-- earlier of its manual close and its closing date.
create or replace function user_dashboard_event_surveys(p_user_id uuid)
returns table (
    answered boolean,
    closed_at timestamptz,
    event_survey_id uuid,
    state text
) as $$
    with candidates as (
        select s.event_survey_id
        from event_attendee ea
        join event_survey s on s.event_id = ea.event_id
        where ea.user_id = p_user_id
        and ea.status = 'confirmed'
        union
        select r.event_survey_id
        from event_survey_response r
        where r.user_id = p_user_id
    )
    select
        ss.answered,
        case when ss.state = 'closed' then least(ss.closed_at, ss.closes_at) end as closed_at,
        ss.event_survey_id,
        ss.state
    from (
        select
            exists (
                select 1
                from event_survey_response r
                where r.event_survey_id = s.event_survey_id
                and r.user_id = p_user_id
            ) as answered,
            s.audience,
            s.closed_at,
            s.closes_at,
            s.event_id,
            s.event_survey_id,
            event_survey_state(s, e) as state
        from candidates cs
        join event_survey s on s.event_survey_id = cs.event_survey_id
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where is_event_survey_public(s, e, g, c)
    ) ss
    where (
        ss.state = 'open'
        and exists (
            select 1
            from event_survey_eligible_users(ss.event_id, ss.audience) eu
            where eu.user_id = p_user_id
        )
    )
    or (ss.state = 'closed' and ss.answered);
$$ language sql stable;
