-- Returns one page of the non-blank answers to a free-text question of a
-- survey of a group event, in response creation order, plus the question
-- position and prompt and the number of answers matching the filters. The
-- filters search the answer text case-insensitively; the page size defaults
-- to 10 and is capped at 50. Answers are plain strings, so the projection
-- carries no ordering keys or respondent identities, and anonymous surveys can
-- be searched too. Null when the question is not a free-text question of a
-- survey of the group event.
create or replace function list_event_survey_text_answers(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_question_id uuid,
    p_filters jsonb
)
returns json as $$
-- Resolve the search and the page bounds
with filters as (
    select
        f.ilike_pattern,
        least(coalesce(f.limit_value, 10), 50) as limit_value,
        coalesce(f.offset_value, 0) as offset_value,
        f.ts_query
    from parse_search_filters(p_filters) f
),
-- Load the free-text question of the survey of the group event
question as (
    select
        definition.position,
        definition.value->>'prompt' as prompt
    from group_dashboard_event_surveys(p_group_id, p_event_id, p_event_survey_id) gs
    cross join lateral jsonb_array_elements((gs.event_survey_row).questions)
        with ordinality as definition(value, position)
    where p_event_survey_id is not null
    and definition.value->>'kind' = 'free-text'
    and case
        -- Compare only question identifiers that are valid uuids
        when pg_input_is_valid(definition.value->>'id', 'uuid')
            then (definition.value->>'id')::uuid
    end = p_question_id
),
-- Collect the answers to the question matching the search
answers as (
    select
        ta.created_at,
        ta.user_id,
        ta.value
    from event_survey_text_answers(p_event_survey_id) ta
    cross join filters f
    where ta.question_id = p_question_id
    and exists (select 1 from question)
    and (f.ts_query is null or ta.value ilike f.ilike_pattern)
),
-- Select the requested page of answers
page as (
    select
        a.created_at,
        a.user_id,
        a.value
    from answers a
    order by a.created_at, a.user_id
    offset (select offset_value from filters)
    limit (select limit_value from filters)
)
-- Project the page with the question details and the total
select json_build_object(
    'answers', coalesce((
        select json_agg(p.value order by p.created_at, p.user_id)
        from page p
    ), '[]'::json),
    'position', q.position,
    'prompt', q.prompt,
    'total', (select count(*) from answers)
)
from question q;
$$ language sql stable;
