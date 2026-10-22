-- Returns one page of the respondents of an identified survey of a group event,
-- in response creation order, plus the total. Each respondent carries the
-- details the respondents table shows: the respondent summary, the ticket
-- title, how many questions the response answers and its dates. The filters
-- search respondents by name, username, company or title; the page size
-- defaults to 20 and is capped at 50. Anonymous surveys never expose
-- respondents. Null when the survey does not belong to the group event.
create or replace function list_event_survey_responses(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_filters jsonb
)
returns json as $$
declare
    v_anonymous boolean;
    v_limit int;
    v_offset int;
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
        raise exception 'responses of anonymous surveys cannot be listed' using errcode = 'OCG01';
    end if;

    -- Resolve the page bounds
    select
        least(coalesce(f.limit_value, 20), 50),
        coalesce(f.offset_value, 0)
    into v_limit, v_offset
    from parse_search_filters(p_filters) f;

    -- Return the requested page of matching respondents with their details
    return (
        with respondents as (
            select
                r.created_at,
                r.user_id
            from event_survey_matching_respondents(p_event_survey_id, p_filters) r
        ),
        page as (
            select
                r.created_at,
                r.user_id
            from respondents r
            order by r.created_at, r.user_id
            offset v_offset
            limit v_limit
        )
        select json_build_object(
            'responses', coalesce((
                select json_agg(
                    json_build_object(
                        'answered_questions_count', d.answered_questions_count,
                        'created_at', epoch_seconds(p.created_at),
                        'user', d.user_summary,

                        'ticket_title', d.ticket_title,
                        'updated_at', epoch_seconds(d.updated_at)
                    )
                    order by p.created_at, p.user_id
                )
                from page p
                cross join lateral event_survey_response_details(p_event_survey_id, p.user_id) d
            ), '[]'::json),
            'total', (select count(*) from respondents)
        )
    );
end;
$$ language plpgsql stable;
