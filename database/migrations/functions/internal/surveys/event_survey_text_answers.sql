-- Returns every non-blank free-text answer of a survey with its question,
-- respondent and response creation time. Answers whose question identifier is
-- not a valid uuid and responses without an answers array are skipped.
-- Callers filter by question and order by created_at, user_id. The function is
-- inlined into its callers, so the responses are read once per query.
create or replace function event_survey_text_answers(
    p_event_survey_id uuid
)
returns table (
    created_at timestamptz,
    question_id uuid,
    user_id uuid,
    value text
) as $$
    select
        r.created_at,
        (answer.value->>'question_id')::uuid,
        r.user_id,
        answer.value->>'value'
    from event_survey_response r
    cross join lateral jsonb_array_elements(
        case
            when jsonb_typeof(r.answers->'answers') = 'array' then r.answers->'answers'
            else '[]'::jsonb
        end
    ) as answer(value)
    where r.event_survey_id = p_event_survey_id
    and jsonb_typeof(answer.value->'value') = 'string'
    and btrim(answer.value->>'value') <> ''
    and pg_input_is_valid(answer.value->>'question_id', 'uuid');
$$ language sql stable;
