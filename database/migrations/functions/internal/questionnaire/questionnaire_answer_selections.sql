-- Returns the option identifiers selected in one questionnaire answers payload.
--
-- Only uuid values are returned, from single-select strings and multi-select
-- arrays, so free text and malformed answers are skipped. Breakdowns match the
-- returned identifiers against the question options, so a uuid typed as free
-- text never counts.
create or replace function questionnaire_answer_selections(p_answers jsonb)
returns table (option_id uuid, question_id uuid) as $$
    select
        selected.value::uuid as option_id,
        (answer.value->>'question_id')::uuid as question_id
    from questionnaire_answer_entries(p_answers) as answer(value)
    cross join lateral (
        select answer.value->>'value' as value
        where jsonb_typeof(answer.value->'value') = 'string'

        union all

        select option_value #>> '{}' as value
        from jsonb_array_elements(
            case
                when jsonb_typeof(answer.value->'value') = 'array' then answer.value->'value'
                else '[]'::jsonb
            end
        ) as option_value
        where jsonb_typeof(option_value) = 'string'
    ) selected
    where pg_input_is_valid(answer.value->>'question_id', 'uuid')
    and pg_input_is_valid(selected.value, 'uuid');
$$ language sql stable;
