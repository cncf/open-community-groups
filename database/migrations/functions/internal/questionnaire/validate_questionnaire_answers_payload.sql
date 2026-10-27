-- Validates questionnaire answers against question definitions.
--
-- Free-text answers are limited to 8000 characters, matching
-- MAX_LEN_QUESTIONNAIRE_ANSWER in the server.
create or replace function validate_questionnaire_answers_payload(
    p_questions jsonb,
    p_answers jsonb
)
returns void as $$
declare
    v_answer jsonb;
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

    -- Accept only an empty submission when no questions are configured
    if jsonb_array_length(p_questions) = 0 then
        -- Reject answers submitted without questions
        if p_answers->'answers' is not null and p_answers->'answers' <> '[]'::jsonb then
            raise exception 'questionnaire answers cannot be submitted when questions are not configured' using errcode = 'OCG01';
        end if;

        return;
    end if;

    -- Require an answers payload object
    if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
        raise exception 'questionnaire answers are required' using errcode = 'OCG01';
    end if;

    -- Require an answers array
    if coalesce(jsonb_typeof(p_answers->'answers'), '') <> 'array' then
        raise exception 'questionnaire answers must contain an answers array' using errcode = 'OCG01';
    end if;

    -- Validate submitted answer identities
    for v_answer in select jsonb_array_elements(p_answers->'answers')
    loop
        -- Reject answer entries that are not objects
        if jsonb_typeof(v_answer) <> 'object' then
            raise exception 'questionnaire answer must be an object' using errcode = 'OCG01';
        end if;

        -- Parse the answered question identifier
        begin
            v_answer_question_id := (v_answer->>'question_id')::uuid;
        exception
            -- Reject question identifiers that are not uuids
            when invalid_text_representation then
                raise exception 'questionnaire answer question_id must be a uuid' using errcode = 'OCG01';
        end;

        -- Reject answers without a question identifier
        if v_answer_question_id is null then
            raise exception 'questionnaire answer question_id must be a uuid' using errcode = 'OCG01';
        end if;

        -- Reject several answers for the same question
        if v_answer_question_id = any(v_answer_question_ids) then
            raise exception 'questionnaire answers must include each question at most once' using errcode = 'OCG01';
        end if;

        -- Track the answered question
        v_answer_question_ids := array_append(v_answer_question_ids, v_answer_question_id);

        -- Reject answers for questions that are not configured
        if not exists (
            select 1
            from jsonb_array_elements(p_questions) question
            where (question->>'id')::uuid = v_answer_question_id
        ) then
            raise exception 'questionnaire answer references an unknown question' using errcode = 'OCG01';
        end if;
    end loop;

    -- Validate answers against each configured question
    for v_question in select jsonb_array_elements(p_questions)
    loop
        -- Load the answer submitted for this question
        v_question_id := (v_question->>'id')::uuid;
        select answer->'value'
        into v_answer_value
        from jsonb_array_elements(p_answers->'answers') answer
        where (answer->>'question_id')::uuid = v_question_id;

        -- Handle unanswered questions
        if not found then
            -- Reject unanswered required questions
            if (v_question->>'required')::boolean then
                raise exception 'required questionnaire answer is missing' using errcode = 'OCG01';
            end if;

            continue;
        end if;

        -- Validate a free-text answer value
        if v_question->>'kind' = 'free-text' then
            -- Require a string value
            if coalesce(jsonb_typeof(v_answer_value), '') <> 'string' then
                raise exception 'free-text questionnaire answer must be a string' using errcode = 'OCG01';
            end if;

            -- Reject values above the free-text length limit
            if length(v_answer_value #>> '{}') > 8000 then
                raise exception 'free-text questionnaire answer is too long' using errcode = 'OCG01';
            end if;

            -- Reject blank values for required questions
            if (v_question->>'required')::boolean and nullif(btrim(v_answer_value #>> '{}'), '') is null then
                raise exception 'required questionnaire answer is empty' using errcode = 'OCG01';
            end if;

        -- Validate a single-select answer value
        elsif v_question->>'kind' = 'single-select' then
            -- Require a string value
            if coalesce(jsonb_typeof(v_answer_value), '') <> 'string' then
                raise exception 'single-select questionnaire answer must be an option id' using errcode = 'OCG01';
            end if;

            -- Parse the selected option identifier
            begin
                v_selected_option_id := (v_answer_value #>> '{}')::uuid;
            exception
                -- Reject values that are not uuids
                when invalid_text_representation then
                    raise exception 'single-select questionnaire answer must be an option id' using errcode = 'OCG01';
            end;

            -- Reject options that the question does not define
            if not exists (
                select 1
                from jsonb_array_elements(v_question->'options') option
                where (option->>'id')::uuid = v_selected_option_id
            ) then
                raise exception 'questionnaire answer references an unknown option' using errcode = 'OCG01';
            end if;

        -- Validate a multi-select answer value
        else
            -- Require an array value
            if coalesce(jsonb_typeof(v_answer_value), '') <> 'array' then
                raise exception 'multi-select questionnaire answer must be an option id array' using errcode = 'OCG01';
            end if;

            -- Reject empty selections for required questions
            if (v_question->>'required')::boolean and jsonb_array_length(v_answer_value) = 0 then
                raise exception 'required questionnaire answer is empty' using errcode = 'OCG01';
            end if;

            -- Collect the options the question defines
            v_option_ids := array(
                select (option->>'id')::uuid
                from jsonb_array_elements(v_question->'options') option
            );

            -- Reset the options selected in this answer
            v_selected_option_ids := array[]::uuid[];

            -- Validate each selected option id
            for v_selected_option in
                select value
                from jsonb_array_elements(v_answer_value) value
            loop
                -- Require string option identifiers
                if jsonb_typeof(v_selected_option) <> 'string' then
                    raise exception 'multi-select questionnaire answer must be an option id array' using errcode = 'OCG01';
                end if;

                -- Parse the selected option identifier
                begin
                    v_selected_option_id := (v_selected_option #>> '{}')::uuid;
                exception
                    -- Reject values that are not uuids
                    when invalid_text_representation then
                        raise exception 'multi-select questionnaire answer must be an option id array' using errcode = 'OCG01';
                end;

                -- Reject options that the question does not define
                if not v_selected_option_id = any(v_option_ids) then
                    raise exception 'questionnaire answer references an unknown option' using errcode = 'OCG01';
                end if;

                -- Reject repeated options
                if v_selected_option_id = any(v_selected_option_ids) then
                    raise exception 'multi-select questionnaire answers cannot repeat options' using errcode = 'OCG01';
                end if;

                -- Track the selected option
                v_selected_option_ids := array_append(v_selected_option_ids, v_selected_option_id);
            end loop;
        end if;
    end loop;
end;
$$ language plpgsql;
