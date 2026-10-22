-- Returns the aggregated results of a survey of a group event: its summary
-- and its questions in definition order. Every question carries its kind,
-- position, prompt, identifier and required flag. Select questions also carry
-- their option breakdown; free-text questions carry their first 10 non-blank
-- answers, in response creation order, and the total. Respondent identities
-- are never returned. Null when the survey does not belong to the group event.
create or replace function get_event_survey_results(
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid
)
returns json as $$
with survey as (
    select
        e as event_row,
        s as event_survey_row
    from event e
    join event_survey s on s.event_id = e.event_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and e.deleted = false
    and s.event_survey_id = p_event_survey_id
),
responses as (
    select
        r.answers,
        r.user_id
    from event_survey_response r
    where r.event_survey_id = p_event_survey_id
    and exists (select 1 from survey)
),
breakdowns as (
    select breakdown.value
    from survey sv
    cross join lateral jsonb_array_elements(
        questionnaire_option_breakdowns(
            (sv.event_survey_row).questions,
            (
                select coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'o', selection.option_id,
                            'q', selection.question_id,
                            'r', r.user_id
                        )
                    ),
                    '[]'::jsonb
                )
                from responses r
                cross join lateral questionnaire_answer_selections(r.answers) selection
            )
        )::jsonb
    ) as breakdown(value)
),
text_answers as (
    select
        ta.question_id,
        row_number() over (
            partition by ta.question_id
            order by ta.created_at, ta.user_id
        ) as rank,
        ta.value
    from survey sv
    cross join lateral event_survey_text_answers((sv.event_survey_row).event_survey_id) ta
)
select jsonb_build_object(
    'questions', coalesce((
        select jsonb_agg(
            jsonb_build_object(
                'kind', question.definition->>'kind',
                'position', question.position,
                'prompt', question.definition->>'prompt',
                'question_id', (question.definition->>'id')::uuid,
                'required', (question.definition->>'required')::boolean,

                'breakdown', (
                    select b.value
                    from breakdowns b
                    where (b.value->>'position')::bigint = question.position
                ),
                'text_answers', case
                    when question.definition->>'kind' = 'free-text' then jsonb_build_object(
                        'answers', coalesce((
                            select jsonb_agg(ta.value order by ta.rank)
                            from text_answers ta
                            where ta.question_id = (question.definition->>'id')::uuid
                            and ta.rank <= 10
                        ), '[]'::jsonb),
                        'total', (
                            select count(*)
                            from text_answers ta
                            where ta.question_id = (question.definition->>'id')::uuid
                        )
                    )
                end
            )
            order by question.position
        )
        from jsonb_array_elements((sv.event_survey_row).questions)
            with ordinality as question(definition, position)
    ), '[]'::jsonb),
    'survey', event_survey_summary_json(sv.event_survey_row, sv.event_row)
)::json
from survey sv;
$$ language sql stable;
