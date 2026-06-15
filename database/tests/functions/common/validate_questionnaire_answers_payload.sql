-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept valid answers for all supported question types
select lives_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "What do you want to learn?",
                    "required": true,
                    "options": []
                },
                {
                    "id": "0c1e0000-0000-0000-0000-000000000002",
                    "kind": "single-select",
                    "prompt": "Meal preference",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "Standard"
                        },
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000005",
                            "label": "Vegetarian"
                        }
                    ]
                },
                {
                    "id": "0c1e0000-0000-0000-0000-000000000003",
                    "kind": "multi-select",
                    "prompt": "Topics",
                    "required": false,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000006",
                            "label": "Rust"
                        },
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000007",
                            "label": "PostgreSQL"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
                        "value": "Scaling communities"
                    },
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000002",
                        "value": "0c1e0000-0000-0000-0000-000000000005"
                    },
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000003",
                        "value": [
                            "0c1e0000-0000-0000-0000-000000000006"
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Required",
                    "required": true,
                    "options": []
                },
                {
                    "id": "0c1e0000-0000-0000-0000-000000000002",
                    "kind": "free-text",
                    "prompt": "Optional",
                    "required": false,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
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
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
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

-- Should reject answers without a question_id
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "value": "Answer"
                    }
                ]
            }'::jsonb
        )
    $$,
    'questionnaire answer question_id must be a uuid',
    'Should reject answers without a question_id'
);

-- Should reject duplicate answers for a question
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
                        "value": "One"
                    },
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": false,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000008",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
                        "value": "0c1e0000-0000-0000-0000-000000000008"
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "multi-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
                        "value": [
                            "0c1e0000-0000-0000-0000-000000000004",
                            "0c1e0000-0000-0000-0000-000000000004"
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "multi-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
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
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001",
                        "value": 42
                    }
                ]
            }'::jsonb
        )
    $$,
    'free-text questionnaire answer must be a string',
    'Should reject non-string free-text answers'
);

-- Should reject free-text answers without a value
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001"
                    }
                ]
            }'::jsonb
        )
    $$,
    'free-text questionnaire answer must be a string',
    'Should reject free-text answers without a value'
);

-- Should reject single-select answers without a value
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001"
                    }
                ]
            }'::jsonb
        )
    $$,
    'single-select questionnaire answer must be an option id',
    'Should reject single-select answers without a value'
);

-- Should reject multi-select answers without a value
select throws_ok(
    $$
        select validate_questionnaire_answers_payload(
            '[
                {
                    "id": "0c1e0000-0000-0000-0000-000000000001",
                    "kind": "multi-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1e0000-0000-0000-0000-000000000004",
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb,
            '{
                "answers": [
                    {
                        "question_id": "0c1e0000-0000-0000-0000-000000000001"
                    }
                ]
            }'::jsonb
        )
    $$,
    'multi-select questionnaire answer must be an option id array',
    'Should reject multi-select answers without a value'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
