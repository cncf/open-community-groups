-- Returns the respondents of a survey whose name, username, company or title
-- matches the text search of the filters, if any, with the creation date of
-- their responses. Only the ordering keys are projected so callers can count,
-- rank and page every match cheaply, then load the details of the rows they
-- return with event_survey_response_details. Callers order by created_at,
-- user_id and keep respondents of anonymous surveys hidden.
create or replace function event_survey_matching_respondents(
    p_event_survey_id uuid,
    p_filters jsonb
)
returns table (
    created_at timestamptz,
    user_id uuid
) as $$
    select
        r.created_at,
        r.user_id
    from event_survey_response r
    join "user" u on u.user_id = r.user_id
    cross join parse_search_filters(p_filters) f
    where r.event_survey_id = p_event_survey_id
    and (
        f.ts_query is null
        or concat_ws(' ', u.name, u.username, u.company, u.title) ilike f.ilike_pattern
    );
$$ language sql stable;
