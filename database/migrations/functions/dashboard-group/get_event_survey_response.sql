-- Returns the response of one respondent to an identified survey of a group
-- event: the respondent details the respondents table shows, the submitted
-- answers, and the position, total and previous and next respondents among the
-- respondents matching the search of the filters, in response creation order.
-- Anonymous surveys never expose respondents. Null when the survey does not
-- belong to the group event or the user has no response matching the search.
create or replace function get_event_survey_response(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_user_id uuid,
    p_filters jsonb
)
returns json as $$
declare
    v_anonymous boolean;
begin
    -- Load the survey of the group event
    select s.anonymous
    into v_anonymous
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and s.event_survey_id = p_event_survey_id;

    -- Report nothing for missing or foreign surveys
    if not found then
        return null;
    end if;

    -- Keep the respondents of anonymous surveys hidden
    if v_anonymous then
        raise exception 'responses of anonymous surveys cannot be viewed' using errcode = 'OCG01';
    end if;

    -- Return the response with its place among the matching respondents
    return (
        with ranked as (
            select
                r.created_at,
                lead(r.user_id) over respondents_order as next_user_id,
                row_number() over respondents_order as position,
                lag(r.user_id) over respondents_order as previous_user_id,
                count(*) over () as total,
                r.user_id
            from event_survey_matching_respondents(p_event_survey_id, p_filters) r
            window respondents_order as (order by r.created_at, r.user_id)
        )
        select json_build_object(
            'answered_questions_count', d.answered_questions_count,
            'answers', d.answers,
            'created_at', epoch_seconds(rk.created_at),
            'user', d.user_summary,

            'ticket_title', d.ticket_title,
            'updated_at', epoch_seconds(d.updated_at),

            'next_user_id', rk.next_user_id,
            'position', rk.position,
            'previous_user_id', rk.previous_user_id,
            'total', rk.total
        )
        from ranked rk
        cross join lateral event_survey_response_details(p_event_survey_id, rk.user_id) d
        where rk.user_id = p_user_id
    );
end;
$$ language plpgsql stable;
