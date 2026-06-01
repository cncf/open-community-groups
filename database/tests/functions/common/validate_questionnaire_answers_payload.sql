-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept valid answers for all supported question types
select lives_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "What do you want to learn?",
                    "required": true,
                    "options": []
                },
                {
                    "id": "90000000-0000-0000-0000-000000000102",
                    "kind": "single-select",
                    "prompt": "Meal preference",
                    "required": true,
                    "options": [
                        {
                            "id": "90000000-0000-0000-0000-000000000201",
                            "label": "Standard"
                        },
                        {
                            "id": "90000000-0000-0000-0000-000000000202",
                            "label": "Vegetarian"
                        }
                    ]
                },
                {
                    "id": "90000000-0000-0000-0000-000000000103",
                    "kind": "multi-select",
                    "prompt": "Topics",
                    "required": false,
                    "options": [
                        {
                            "id": "90000000-0000-0000-0000-000000000203",
                            "label": "Rust"
                        },
                        {
                            "id": "90000000-0000-0000-0000-000000000204",
                            "label": "PostgreSQL"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "Scaling communities"
                    },
                    {
                        "question_id": "90000000-0000-0000-0000-000000000102",
                        "value": "90000000-0000-0000-0000-000000000202"
                    },
                    {
                        "question_id": "90000000-0000-0000-0000-000000000103",
                        "value": [
                            "90000000-0000-0000-0000-000000000203"
                        ]
                    }
                ]
            }'::jsonb
        )
    $$,
    'Should accept valid answers for all supported question types'
);

-- Should accept omitted optional answers
select lives_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Required",
                    "required": true,
                    "options": []
                },
                {
                    "id": "90000000-0000-0000-0000-000000000102",
                    "kind": "free-text",
                    "prompt": "Optional",
                    "required": false,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "Answered"
                    }
                ]
            }'::jsonb
        )
    $$,
    'Should accept omitted optional answers'
);

-- Should reject answers when questions are not configured
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "Answered"
                    }
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answers cannot be submitted when questions are not configured',
    'Should reject answers when questions are not configured'
);

-- Should reject missing answers when questions exist
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            null::jsonb
        )
    $$,
    'questionnaire answers are required',
    'Should reject missing answers when questions exist'
);

-- Should require an answers array
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": {}
            }'::jsonb
        )
    $$,
    'questionnaire answers must contain an answers array',
    'Should require an answers array'
);

-- Should reject non-object answers
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    "bad"
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answer must be an object',
    'Should reject non-object answers'
);

-- Should reject duplicate answers for a question
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "One"
                    },
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "Two"
                    }
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answers must include each question at most once',
    'Should reject duplicate answers for a question'
);

-- Should reject answers for unknown questions
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": false,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000999",
                        "value": "Answer"
                    }
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answer references an unknown question',
    'Should reject answers for unknown questions'
);

-- Should reject missing required answers
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": []
            }'::jsonb
        )
    $$,
    'required questionnaire answer is missing',
    'Should reject missing required answers'
);

-- Should reject empty required free-text answers
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "  "
                    }
                ]
            }'::jsonb
        )
    $$,
    'required questionnaire answer is empty',
    'Should reject empty required free-text answers'
);

-- Should reject unknown single-select options
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "90000000-0000-0000-0000-000000000201",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": "90000000-0000-0000-0000-000000000999"
                    }
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answer references an unknown option',
    'Should reject unknown single-select options'
);

-- Should reject duplicate multi-select options
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "multi-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "90000000-0000-0000-0000-000000000201",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": [
                            "90000000-0000-0000-0000-000000000201",
                            "90000000-0000-0000-0000-000000000201"
                        ]
                    }
                ]
            }'::jsonb
        )
    $$,
    'multi-select questionnaire answers cannot repeat options',
    'Should reject duplicate multi-select options'
);

-- Should reject invalid multi-select option ids
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "multi-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "90000000-0000-0000-0000-000000000201",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": [
                            "bad"
                        ]
                    }
                ]
            }'::jsonb
        )
    $$,
    'multi-select questionnaire answer must be an option id array',
    'Should reject invalid multi-select option ids'
);

-- Should reject non-string free-text answers
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "90000000-0000-0000-0000-000000000101",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "90000000-0000-0000-0000-000000000101",
                        "value": 42
                    }
                ]
            }'::jsonb
        )
    $$,
    'free-text questionnaire answer must be a string',
    'Should reject non-string free-text answers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
