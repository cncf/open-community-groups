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
        raise exception 'questionnaire questions must be an array';
    end if;

    -- Validate each question definition
    for v_question in select jsonb_array_elements(p_questions)
    loop
        if jsonb_typeof(v_question) <> 'object' then
            raise exception 'questionnaire question must be an object';
        end if;

        -- Validate question identity
        begin
            v_question_id := (v_question->>'id')::uuid;
        exception when invalid_text_representation then
            raise exception 'questionnaire question id must be a uuid';
        end;

        if v_question_id = any(v_question_ids) then
            raise exception 'questionnaire question ids must be unique';
        end if;
        v_question_ids := array_append(v_question_ids, v_question_id);

        -- Validate question content
        if nullif(btrim(v_question->>'prompt'), '') is null then
            raise exception 'questionnaire question prompt is required';
        end if;

        v_kind := v_question->>'kind';
        if v_kind not in ('free-text', 'multi-select', 'single-select') then
            raise exception 'questionnaire question kind is invalid';
        end if;

        if coalesce(jsonb_typeof(v_question->'required'), '') <> 'boolean' then
            raise exception 'questionnaire question required must be a boolean';
        end if;

        -- Validate options for the question kind
        v_options := coalesce(v_question->'options', '[]'::jsonb);
        if jsonb_typeof(v_options) <> 'array' then
            raise exception 'questionnaire question options must be an array';
        end if;

        if v_kind = 'free-text' and jsonb_array_length(v_options) <> 0 then
            raise exception 'free-text questionnaire questions cannot define options';
        end if;

        if v_kind in ('multi-select', 'single-select') and jsonb_array_length(v_options) = 0 then
            raise exception 'select questionnaire questions require options';
        end if;

        -- Validate each option definition
        v_option_ids := array[]::uuid[];
        for v_option in select jsonb_array_elements(v_options)
        loop
            if jsonb_typeof(v_option) <> 'object' then
                raise exception 'questionnaire question option must be an object';
            end if;

            -- Validate option identity
            begin
                v_option_id := (v_option->>'id')::uuid;
            exception when invalid_text_representation then
                raise exception 'questionnaire question option id must be a uuid';
            end;

            if v_option_id = any(v_option_ids) then
                raise exception 'questionnaire question option ids must be unique per question';
            end if;
            v_option_ids := array_append(v_option_ids, v_option_id);

            -- Validate option content
            if nullif(btrim(v_option->>'label'), '') is null then
                raise exception 'questionnaire question option label is required';
            end if;
        end loop;
    end loop;
end;
$$ language plpgsql;
