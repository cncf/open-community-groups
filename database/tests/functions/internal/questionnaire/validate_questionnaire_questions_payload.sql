-- Tests validating questionnaire question definitions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

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

-- Should reject blank option labels
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
                            "label": " "
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question option label is required',
    'Should reject blank option labels'
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
    'OCG01',
    'questionnaire question prompt is required',
    'Should reject blank prompts'
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
    'OCG01',
    'questionnaire question option ids must be unique per question',
    'Should reject duplicate option ids per question'
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
    'OCG01',
    'questionnaire question ids must be unique',
    'Should reject duplicate question ids'
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
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should reject invalid question ids'
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
    'OCG01',
    'questionnaire questions must be an array',
    'Should reject non-array payloads'
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
    'OCG01',
    'questionnaire question required must be a boolean',
    'Should reject non-boolean required flags'
);

-- Should reject non-object questions
select throws_ok(
    $$select validate_questionnaire_questions_payload('["not-an-object"]'::jsonb)$$,
    'OCG01',
    'questionnaire question must be an object',
    'Should reject non-object questions'
);

-- Should reject non-string option labels
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
                            "label": 1
                        }
                    ]
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question option label is required',
    'Should reject non-string option labels'
);

-- Should reject non-string prompts
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": "free-text",
                    "prompt": 1,
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question prompt is required',
    'Should reject non-string prompts'
);

-- Should reject non-string question kinds
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": 1,
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question kind is invalid',
    'Should reject non-string question kinds'
);

-- Should reject null payloads
select throws_ok(
    $$select validate_questionnaire_questions_payload(null::jsonb)$$,
    'OCG01',
    'questionnaire questions must be an array',
    'Should reject null payloads'
);

-- Should reject null question kinds
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "kind": null,
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question kind is invalid',
    'Should reject null question kinds'
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
    'OCG01',
    'free-text questionnaire questions cannot define options',
    'Should reject options for free-text questions'
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
    'OCG01',
    'questionnaire question option id must be a uuid',
    'Should reject options without ids'
);

-- Should reject questions without a kind
select throws_ok(
    $$
        select validate_questionnaire_questions_payload(
            '[
                {
                    "id": "0c1f0000-0000-0000-0000-000000000001",
                    "prompt": "Question",
                    "required": true,
                    "options": []
                }
            ]'::jsonb
        )
    $$,
    'OCG01',
    'questionnaire question kind is invalid',
    'Should reject questions without a kind'
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
    'OCG01',
    'questionnaire question id must be a uuid',
    'Should reject questions without ids'
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
    'OCG01',
    'select questionnaire questions require options',
    'Should reject select questions without options'
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
    'OCG01',
    'questionnaire question kind is invalid',
    'Should reject unsupported question kinds'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
