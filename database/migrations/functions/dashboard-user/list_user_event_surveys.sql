-- Returns one page of the open surveys a user is eligible to answer across
-- public events, plus their total. Unanswered surveys come first, then by
-- closing date, effective opening and id. The page size defaults to 10 and is
-- capped at 50.
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
        -- Collect the open surveys of public events the user can answer
        surveys as (
            select
                exists (
                    select 1
                    from event_survey_response r
                    where r.event_survey_id = s.event_survey_id
                    and r.user_id = p_user_id
                ) as answered,
                s.closes_at,
                event_survey_effective_opens_at(s, e) as effective_opens_at,
                e.name as event_name,
                s.event_survey_id,
                g.name as group_name,
                e.timezone,
                s.title
            from event_survey s
            join event e on e.event_id = s.event_id
            join "group" g on g.group_id = e.group_id
            join community c on c.community_id = g.community_id
            where is_event_survey_public(s, e, g, c)
            and event_survey_state(s, e) = 'open'
            and exists (
                select 1
                from event_survey_eligible_users(e.event_id, s.audience) eu
                where eu.user_id = p_user_id
            )
        ),
        -- Select the requested page in display order
        surveys_page as (
            select *
            from surveys s
            order by s.answered, s.closes_at nulls last, s.effective_opens_at, s.event_survey_id
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
                    'timezone', sp.timezone,
                    'title', sp.title,

                    'closes_at', epoch_seconds(sp.closes_at)
                )
                order by sp.answered, sp.closes_at nulls last, sp.effective_opens_at, sp.event_survey_id
            )
            from surveys_page sp
        ), '[]'::json),
        'total', (select count(*) from surveys)
    );
$$ language sql stable;
