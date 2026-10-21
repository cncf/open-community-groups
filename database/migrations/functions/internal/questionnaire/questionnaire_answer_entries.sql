-- Returns the answers of a questionnaire answers payload, or none when the
-- payload has no answers array.
create or replace function questionnaire_answer_entries(p_answers jsonb)
returns setof jsonb as $$
    select answer.value
    from jsonb_array_elements(
        case
            when jsonb_typeof(p_answers->'answers') = 'array' then p_answers->'answers'
            else '[]'::jsonb
        end
    ) as answer(value);
$$ language sql immutable;
