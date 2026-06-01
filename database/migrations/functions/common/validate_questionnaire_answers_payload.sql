-- Validates questionnaire answers against question definitions.
create or replace function validate_questionnaire_answers_payload(
    p_questions jsonb,
    p_answers jsonb
)
returns void as $$
declare
    v_answer jsonb;
    v_answer_count int;
    v_answer_question_id uuid;
    v_answer_question_ids uuid[] := array[]::uuid[];
    v_answer_value jsonb;
    v_option_ids uuid[];
    v_question jsonb;
    v_question_id uuid;
    v_selected_option jsonb;
    v_selected_option_id uuid;
    v_selected_option_ids uuid[];
begin
    -- Validate question definitions before matching submitted answers
    perform validate_questionnaire_questions_payload(p_questions);

    -- Reject answers when no questions are configured
    if jsonb_array_length(p_questions) = 0 then
        if p_answers is not null and coalesce(jsonb_array_length(p_answers->'answers'), 0) > 0 then
            raise exception 'questionnaire answers cannot be submitted when questions are not configured';
        end if;

        return;
    end if;

    -- Validate answers payload shape
    if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
        raise exception 'questionnaire answers are required';
    end if;

    if coalesce(jsonb_typeof(p_answers->'answers'), '') <> 'array' then
        raise exception 'questionnaire answers must contain an answers array';
    end if;

    -- Validate submitted answer identities
    for v_answer in select jsonb_array_elements(p_answers->'answers')
    loop
        if jsonb_typeof(v_answer) <> 'object' then
            raise exception 'questionnaire answer must be an object';
        end if;

        begin
            v_answer_question_id := (v_answer->>'question_id')::uuid;
        exception when invalid_text_representation then
            raise exception 'questionnaire answer question_id must be a uuid';
        end;

        if v_answer_question_id = any(v_answer_question_ids) then
            raise exception 'questionnaire answers must include each question at most once';
        end if;
        v_answer_question_ids := array_append(v_answer_question_ids, v_answer_question_id);

        if not exists (
            select 1
            from jsonb_array_elements(p_questions) question
            where (question->>'id')::uuid = v_answer_question_id
        ) then
            raise exception 'questionnaire answer references an unknown question';
        end if;
    end loop;

    -- Validate answers against each configured question
    for v_question in select jsonb_array_elements(p_questions)
    loop
        v_question_id := (v_question->>'id')::uuid;

        -- Locate the answer (if any) submitted for this question
        select count(*)
        into v_answer_count
        from jsonb_array_elements(p_answers->'answers') answer
        where (answer->>'question_id')::uuid = v_question_id;

        if v_answer_count = 0 then
            if (v_question->>'required')::boolean then
                raise exception 'required questionnaire answer is missing';
            end if;

            continue;
        end if;

        select answer->'value'
        into v_answer_value
        from jsonb_array_elements(p_answers->'answers') answer
        where (answer->>'question_id')::uuid = v_question_id
        limit 1;

        -- Validate the answer value matches the question kind
        if v_question->>'kind' = 'free-text' then
            -- Validate free-text answer value
            if jsonb_typeof(v_answer_value) <> 'string' then
                raise exception 'free-text questionnaire answer must be a string';
            end if;

            if (v_question->>'required')::boolean and nullif(btrim(v_answer_value #>> '{}'), '') is null then
                raise exception 'required questionnaire answer is empty';
            end if;
        elsif v_question->>'kind' = 'single-select' then
            -- Validate single-select answer value
            if jsonb_typeof(v_answer_value) <> 'string' then
                raise exception 'single-select questionnaire answer must be an option id';
            end if;

            begin
                v_selected_option_id := (v_answer_value #>> '{}')::uuid;
            exception when invalid_text_representation then
                raise exception 'single-select questionnaire answer must be an option id';
            end;

            if not exists (
                select 1
                from jsonb_array_elements(v_question->'options') option
                where (option->>'id')::uuid = v_selected_option_id
            ) then
                raise exception 'questionnaire answer references an unknown option';
            end if;
        else
            -- Validate multi-select answer value
            if jsonb_typeof(v_answer_value) <> 'array' then
                raise exception 'multi-select questionnaire answer must be an option id array';
            end if;

            if (v_question->>'required')::boolean and jsonb_array_length(v_answer_value) = 0 then
                raise exception 'required questionnaire answer is empty';
            end if;

            v_option_ids := array(
                select (option->>'id')::uuid
                from jsonb_array_elements(v_question->'options') option
            );
            v_selected_option_ids := array[]::uuid[];

            -- Validate each selected option id
            for v_selected_option in
                select value
                from jsonb_array_elements(v_answer_value) value
            loop
                if jsonb_typeof(v_selected_option) <> 'string' then
                    raise exception 'multi-select questionnaire answer must be an option id array';
                end if;

                begin
                    v_selected_option_id := (v_selected_option #>> '{}')::uuid;
                exception when invalid_text_representation then
                    raise exception 'multi-select questionnaire answer must be an option id array';
                end;

                if not v_selected_option_id = any(v_option_ids) then
                    raise exception 'questionnaire answer references an unknown option';
                end if;

                if v_selected_option_id = any(v_selected_option_ids) then
                    raise exception 'multi-select questionnaire answers cannot repeat options';
                end if;

                v_selected_option_ids := array_append(v_selected_option_ids, v_selected_option_id);
            end loop;
        end if;
    end loop;
end;
$$ language plpgsql;
