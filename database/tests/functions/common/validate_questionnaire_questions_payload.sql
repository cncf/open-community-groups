-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept an empty questions array
select lives_ok(
    $$select validate_questionnaire_questions_payload('[]'::jsonb)$$,
    'Should accept an empty questions array'
);

-- Should accept supported question types with valid options
select lives_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "What do you want to learn?",
                    "required": true,
                    "options": []
                },
                {
                    "id": "0c1f0000-0000-0000-0000-000000000002",
                    "kind": "single-select",
                    "prompt": "Meal preference",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000004",
                            "label": "Standard"
                        },
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000005",
                            "label": "Vegetarian"
                        }
                    ]
                },
                {
                    "id": "0c1f0000-0000-0000-0000-000000000003",
                    "kind": "multi-select",
                    "prompt": "Topics",
                    "required": false,
                    "options": [
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000006",
                            "label": "Rust"
                        },
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000007",
                            "label": "PostgreSQL"
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'Should accept supported question types with valid options'
);

-- Should reject null payloads
select throws_ok(
    $$select validate_questionnaire_questions_payload(null::jsonb)$$,
    'questionnaire questions must be an array',
    'Should reject null payloads'
);

-- Should reject non-array payloads
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '{
                "id": "0c1f0000-0000-0000-0000-000000000001"
            }'::jsonb
        )
    $$,
    'questionnaire questions must be an array',
    'Should reject non-array payloads'
);

-- Should reject non-object questions
select throws_ok(
    $$select validate_questionnaire_questions_payload('["not-an-object"]'::jsonb)$$,
    'questionnaire question must be an object',
    'Should reject non-object questions'
);

-- Should reject invalid question ids
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "bad",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question id must be a uuid',
    'Should reject invalid question ids'
);

-- Should reject questions without ids
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question id must be a uuid',
    'Should reject questions without ids'
);

-- Should reject duplicate question ids
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question one",
                    "required": true,
                    "options": []
                },
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question two",
                    "required": false,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question ids must be unique',
    'Should reject duplicate question ids'
);

-- Should reject blank prompts
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": " ",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question prompt is required',
    'Should reject blank prompts'
);

-- Should reject unsupported question kinds
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "date",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question kind is invalid',
    'Should reject unsupported question kinds'
);

-- Should reject non-boolean required flags
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": "yes",
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question required must be a boolean',
    'Should reject non-boolean required flags'
);

-- Should reject options for free-text questions
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000004",
                            "label": "Option"
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'free-text questionnaire questions cannot define options',
    'Should reject options for free-text questions'
);

-- Should reject select questions without options
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'select questionnaire questions require options',
    'Should reject select questions without options'
);

-- Should reject options without ids
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "label": "One"
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question option id must be a uuid',
    'Should reject options without ids'
);

-- Should reject duplicate option ids per question
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "single-select",
                    "prompt": "Question",
                    "required": true,
                    "options": [
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000004",
                            "label": "One"
                        },
                        {
                            "id": "0c1f0000-0000-0000-0000-000000000004",
                            "label": "Two"
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'questionnaire question option ids must be unique per question',
    'Should reject duplicate option ids per question'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
