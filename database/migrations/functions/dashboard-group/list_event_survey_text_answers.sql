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
with filters as (
    select
        f.ilike_pattern,
        least(coalesce(f.limit_value, 10), 50) as limit_value,
        coalesce(f.offset_value, 0) as offset_value,
        f.ts_query
    from parse_search_filters(p_filters) f
),
question as (
    select
        definition.position,
        definition.value->>'prompt' as prompt
    from event e
    join event_survey s on s.event_id = e.event_id
    cross join lateral jsonb_array_elements(s.questions)
        with ordinality as definition(value, position)
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and s.event_survey_id = p_event_survey_id
    and definition.value->>'kind' = 'free-text'
    and case
        when pg_input_is_valid(definition.value->>'id', 'uuid')
            then (definition.value->>'id')::uuid
    end = p_question_id
),
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
