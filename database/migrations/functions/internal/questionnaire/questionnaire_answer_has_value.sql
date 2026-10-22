-- Returns whether a questionnaire answer value answers its question: a
-- non-blank text or at least one selected option.
create or replace function questionnaire_answer_has_value(p_value jsonb)
returns boolean as $$
    select case jsonb_typeof(p_value)
        when 'array' then jsonb_array_length(p_value) > 0
        when 'string' then btrim(p_value #>> '{}') <> ''
        else false
    end;
$$ language sql immutable;
