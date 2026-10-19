-- Validates reusable questionnaire question definitions.
create or replace function validate_questionnaire_questions_payload(p_questions jsonb)
returns void as $$
declare
    v_kind text;
    v_option jsonb;
    v_option_id uuid;
    v_option_ids uuid[] := array[]::uuid[];
    v_options jsonb;
    v_question jsonb;
    v_question_id uuid;
    v_question_ids uuid[] := array[]::uuid[];
begin
    -- Validate top-level questions payload shape
    if p_questions is null or jsonb_typeof(p_questions) <> 'array' then
        raise exception 'questionnaire questions must be an array' using errcode = 'OCG01';
    end if;

    -- Validate each question definition
    for v_question in select jsonb_array_elements(p_questions)
    loop
        -- Reject question entries that are not objects
        if jsonb_typeof(v_question) <> 'object' then
            raise exception 'questionnaire question must be an object' using errcode = 'OCG01';
        end if;

        -- Parse the question identifier
        begin
            v_question_id := (v_question->>'id')::uuid;
        exception
            -- Reject identifiers that are not uuids
            when invalid_text_representation then
                raise exception 'questionnaire question id must be a uuid' using errcode = 'OCG01';
        end;

        -- Reject questions without an identifier
        if v_question_id is null then
            raise exception 'questionnaire question id must be a uuid' using errcode = 'OCG01';
        end if;

        -- Reject identifiers already used by another question
        if v_question_id = any(v_question_ids) then
            raise exception 'questionnaire question ids must be unique' using errcode = 'OCG01';
        end if;
        v_question_ids := array_append(v_question_ids, v_question_id);

        -- Require a non-blank string prompt
        if jsonb_typeof(v_question->'prompt') is distinct from 'string'
            or nullif(btrim(v_question->>'prompt'), '') is null
        then
            raise exception 'questionnaire question prompt is required' using errcode = 'OCG01';
        end if;

        -- Require a supported string kind
        v_kind := v_question->>'kind';
        if jsonb_typeof(v_question->'kind') is distinct from 'string'
            or v_kind not in ('free-text', 'multi-select', 'single-select')
        then
            raise exception 'questionnaire question kind is invalid' using errcode = 'OCG01';
        end if;

        -- Require a boolean required flag
        if coalesce(jsonb_typeof(v_question->'required'), '') <> 'boolean' then
            raise exception 'questionnaire question required must be a boolean' using errcode = 'OCG01';
        end if;

        -- Require options to be an array when present
        v_options := coalesce(v_question->'options', '[]'::jsonb);
        if jsonb_typeof(v_options) <> 'array' then
            raise exception 'questionnaire question options must be an array' using errcode = 'OCG01';
        end if;

        -- Reject options on free-text questions
        if v_kind = 'free-text' and jsonb_array_length(v_options) <> 0 then
            raise exception 'free-text questionnaire questions cannot define options' using errcode = 'OCG01';
        end if;

        -- Require options on select questions
        if v_kind in ('multi-select', 'single-select') and jsonb_array_length(v_options) = 0 then
            raise exception 'select questionnaire questions require options' using errcode = 'OCG01';
        end if;

        -- Validate each option definition
        v_option_ids := array[]::uuid[];
        for v_option in select jsonb_array_elements(v_options)
        loop
            -- Reject option entries that are not objects
            if jsonb_typeof(v_option) <> 'object' then
                raise exception 'questionnaire question option must be an object' using errcode = 'OCG01';
            end if;

            -- Parse the option identifier
            begin
                v_option_id := (v_option->>'id')::uuid;
            exception
                -- Reject identifiers that are not uuids
                when invalid_text_representation then
                    raise exception 'questionnaire question option id must be a uuid' using errcode = 'OCG01';
            end;

            -- Reject options without an identifier
            if v_option_id is null then
                raise exception 'questionnaire question option id must be a uuid' using errcode = 'OCG01';
            end if;

            -- Reject identifiers already used by another option of the question
            if v_option_id = any(v_option_ids) then
                raise exception 'questionnaire question option ids must be unique per question' using errcode = 'OCG01';
            end if;
            v_option_ids := array_append(v_option_ids, v_option_id);

            -- Require a non-blank string label
            if jsonb_typeof(v_option->'label') is distinct from 'string'
                or nullif(btrim(v_option->>'label'), '') is null
            then
                raise exception 'questionnaire question option label is required' using errcode = 'OCG01';
            end if;
        end loop;
    end loop;
end;
$$ language plpgsql;
