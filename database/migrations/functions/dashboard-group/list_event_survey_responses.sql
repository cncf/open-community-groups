-- Returns one page of the responses to an identified survey of a group event,
-- in creation order, with the respondent details the attendee list shows,
-- plus the total. The page size defaults to 20 and is capped at 50. Anonymous
-- surveys never expose respondents. Null when the survey does not belong to
-- the group event.
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

    -- Return the requested page with its respondents
    return (
        with page as (
            select
                r.answers,
                r.created_at,
                r.updated_at,
                r.user_id
            from event_survey_response r
            where r.event_survey_id = p_event_survey_id
            order by r.created_at, r.user_id
            offset v_offset
            limit v_limit
        )
        select json_build_object(
            'responses', coalesce((
                select json_agg(
                    json_build_object(
                        'answers', p.answers,
                        'created_at', epoch_seconds(p.created_at),
                        'user', public_user_summary(u),

                        'updated_at', epoch_seconds(p.updated_at)
                    )
                    order by p.created_at, p.user_id
                )
                from page p
                join "user" u on u.user_id = p.user_id
            ), '[]'::json),
            'total', (
                select count(*)
                from event_survey_response r
                where r.event_survey_id = p_event_survey_id
            )
        )
    );
end;
$$ language plpgsql stable;
