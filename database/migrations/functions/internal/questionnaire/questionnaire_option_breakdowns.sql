-- Returns the option breakdowns of the select questions of a questionnaire.
--
-- p_selections is an array of {"o": option_id, "q": question_id, "r":
-- respondent} objects built by the caller. Each breakdown counts the
-- selections of the question's current options, in definition order, and the
-- distinct respondents with at least one of them. position is the 1-based
-- index of the question among every question, free-text ones included.
create or replace function questionnaire_option_breakdowns(
    p_questions jsonb,
    p_selections jsonb
)
returns json as $$
with questions as (
    select
        question.definition,
        question.position
    from jsonb_array_elements(
        case
            when jsonb_typeof(p_questions) = 'array' then p_questions
            else '[]'::jsonb
        end
    ) with ordinality as question(definition, position)
    where question.definition->>'kind' in ('multi-select', 'single-select')
),
selections as (
    select
        (selection.value->>'o')::uuid as option_id,
        (selection.value->>'q')::uuid as question_id,
        selection.value->>'r' as respondent
    from jsonb_array_elements(
        case
            when jsonb_typeof(p_selections) = 'array' then p_selections
            else '[]'::jsonb
        end
    ) as selection(value)
),
option_selections as (
    select
        (question_option.definition->>'id')::uuid as option_id,
        q.position,
        s.respondent
    from questions q
    cross join lateral jsonb_array_elements(q.definition->'options')
        as question_option(definition)
    join selections s
        on s.question_id = (q.definition->>'id')::uuid
        and s.option_id = (question_option.definition->>'id')::uuid
)
select coalesce(
    json_agg(
        json_build_object(
            'kind', q.definition->>'kind',
            'options', coalesce((
                select json_agg(
                    json_build_object(
                        'count', (
                            select count(*)
                            from option_selections os
                            where os.position = q.position
                            and os.option_id = (question_option.definition->>'id')::uuid
                        ),
                        'label', question_option.definition->>'label',
                        'option_id', (question_option.definition->>'id')::uuid
                    )
                    order by question_option.position
                )
                from jsonb_array_elements(q.definition->'options')
                    with ordinality as question_option(definition, position)
            ), '[]'::json),
            'position', q.position,
            'prompt', q.definition->>'prompt',
            'question_id', (q.definition->>'id')::uuid,
            'respondents', (
                select count(distinct os.respondent)
                from option_selections os
                where os.position = q.position
            ),
            'selections', (
                select count(*)
                from option_selections os
                where os.position = q.position
            )
        )
        order by q.position
    ),
    '[]'::json
)
from questions q;
$$ language sql immutable;
