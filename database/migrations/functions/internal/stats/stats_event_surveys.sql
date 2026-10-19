-- Returns the survey summary of an event for analytics.
--
-- Rows cover every survey that is not a draft, ordered by creation, with the
-- live counts of event_survey_summary_json. The totals add up the surveys that
-- already opened (open or closed) and are the inputs of the weighted overall
-- response rate: total eligible respondents divided by total eligible users.
create or replace function stats_event_surveys(p_event event)
returns json as $$
with surveys as (
    select
        s.created_at,
        s.event_survey_id,
        event_survey_summary_json(s, p_event) as summary
    from event_survey s
    where s.event_id = p_event.event_id
    and s.status = 'ready'
)
select json_build_object(
    'surveys', coalesce(
        json_agg(
            json_build_object(
                'eligible_count', (sv.summary->>'eligible_count')::bigint,
                'eligible_respondents_count', (sv.summary->>'eligible_respondents_count')::bigint,
                'event_survey_id', sv.event_survey_id,
                'responses_count', (sv.summary->>'responses_count')::bigint,
                'state', sv.summary->>'state',
                'title', sv.summary->>'title'
            )
            order by sv.created_at, sv.event_survey_id
        ),
        '[]'::json
    ),
    'total_eligible_count', coalesce(
        sum((sv.summary->>'eligible_count')::bigint)
            filter (where sv.summary->>'state' in ('closed', 'open')),
        0
    )::bigint,
    'total_eligible_respondents_count', coalesce(
        sum((sv.summary->>'eligible_respondents_count')::bigint)
            filter (where sv.summary->>'state' in ('closed', 'open')),
        0
    )::bigint
)
from surveys sv;
$$ language sql stable;
