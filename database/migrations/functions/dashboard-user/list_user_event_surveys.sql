-- Returns one page of the surveys a user reaches from the dashboard, plus their
-- total: the open surveys the user can answer, unanswered first, then by
-- closing date, effective opening and id, followed by the closed surveys the
-- user answered, most recently closed first. The page size defaults to 10 and
-- is capped at 50.
create or replace function list_user_event_surveys(p_user_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Normalize the pagination filters
        filters as (
            select
                least(coalesce(f.limit_value, 10), 50) as limit_value,
                coalesce(f.offset_value, 0) as offset_value
            from parse_search_filters(p_filters) f
        ),
        -- Collect the surveys the user reaches with their event details
        surveys as (
            select
                us.answered,
                us.closed_at,
                s.closes_at,
                event_survey_effective_opens_at(s, e) as effective_opens_at,
                e.name as event_name,
                s.event_survey_id,
                g.name as group_name,
                us.state,
                e.timezone,
                s.title
            from user_dashboard_event_surveys(p_user_id) us
            join event_survey s on s.event_survey_id = us.event_survey_id
            join event e on e.event_id = s.event_id
            join "group" g on g.group_id = e.group_id
        ),
        -- Select the requested page in display order
        surveys_page as (
            select *
            from surveys s
            order by
                s.state = 'closed',
                s.answered,
                s.closed_at desc nulls last,
                s.closes_at nulls last,
                s.effective_opens_at,
                s.event_survey_id
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        )
    -- Project the page and the total into the Rust JSON contract
    select json_build_object(
        'surveys', coalesce((
            select json_agg(
                json_build_object(
                    'answered', sp.answered,
                    'event_name', sp.event_name,
                    'event_survey_id', sp.event_survey_id,
                    'group_name', sp.group_name,
                    'state', sp.state,
                    'timezone', sp.timezone,
                    'title', sp.title,

                    'closed_at', epoch_seconds(sp.closed_at),
                    'closes_at', epoch_seconds(sp.closes_at)
                )
                order by
                    sp.state = 'closed',
                    sp.answered,
                    sp.closed_at desc nulls last,
                    sp.closes_at nulls last,
                    sp.effective_opens_at,
                    sp.event_survey_id
            )
            from surveys_page sp
        ), '[]'::json),
        'total', (select count(*) from surveys)
    );
$$ language sql stable;
