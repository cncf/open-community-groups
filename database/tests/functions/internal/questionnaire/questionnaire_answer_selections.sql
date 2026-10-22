-- Tests extracting the selected option ids of a questionnaire answers payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore answers with an invalid question id
select is_empty(
    $$
        select *
        from questionnaire_answer_selections(
            '{
                "answers": [
                    {"question_id": "bad", "value": "0c210000-0000-0000-0000-000000000004"},
                    {"value": "0c210000-0000-0000-0000-000000000005"}
                ]
            }'::jsonb
        )
    $$,
    'Should ignore answers with an invalid question id'
);

-- Should ignore free text and values that are not uuids
select is_empty(
    $$
        select *
        from questionnaire_answer_selections(
            '{
                "answers": [
                    {"question_id": "0c210000-0000-0000-0000-000000000001", "value": "Free text"},
                    {"question_id": "0c210000-0000-0000-0000-000000000002", "value": ["Not an option", 1, {"id": "x"}]},
                    {"question_id": "0c210000-0000-0000-0000-000000000003", "value": 1},
                    {"question_id": "0c210000-0000-0000-0000-000000000003"},
                    "not-an-object"
                ]
            }'::jsonb
        )
    $$,
    'Should ignore free text and values that are not uuids'
);

-- Should return each option id of a multi-select answer
select results_eq(
    $$
        select option_id, question_id
        from questionnaire_answer_selections(
            '{
                "answers": [
                    {
                        "question_id": "0c210000-0000-0000-0000-000000000002",
                        "value": [
                            "0c210000-0000-0000-0000-000000000006",
                            "Not an option",
                            "0c210000-0000-0000-0000-000000000007"
                        ]
                    }
                ]
            }'::jsonb
        )
        order by option_id
    $$,
    $$
        values
            ('0c210000-0000-0000-0000-000000000006'::uuid, '0c210000-0000-0000-0000-000000000002'::uuid),
            ('0c210000-0000-0000-0000-000000000007'::uuid, '0c210000-0000-0000-0000-000000000002'::uuid)
    $$,
    'Should return each option id of a multi-select answer'
);

-- Should return nothing for payloads without an answers array
select is_empty(
    $$
        select * from questionnaire_answer_selections(null)
        union all
        select * from questionnaire_answer_selections('{}'::jsonb)
        union all
        select * from questionnaire_answer_selections('{"answers": {}}'::jsonb)
        union all
        select * from questionnaire_answer_selections('[]'::jsonb)
    $$,
    'Should return nothing for payloads without an answers array'
);

-- Should return the option id of a single-select answer
select results_eq(
    $$
        select option_id, question_id
        from questionnaire_answer_selections(
            '{
                "answers": [
                    {
                        "question_id": "0c210000-0000-0000-0000-000000000001",
                        "value": "0c210000-0000-0000-0000-000000000004"
                    }
                ]
            }'::jsonb
        )
    $$,
    $$
        values ('0c210000-0000-0000-0000-000000000004'::uuid, '0c210000-0000-0000-0000-000000000001'::uuid)
    $$,
    'Should return the option id of a single-select answer'
);

-- Should return the selections of every answer in the payload
select results_eq(
    $$
        select option_id, question_id
        from questionnaire_answer_selections(
            '{
                "answers": [
                    {
                        "question_id": "0c210000-0000-0000-0000-000000000001",
                        "value": "0c210000-0000-0000-0000-000000000004"
                    },
                    {
                        "question_id": "0c210000-0000-0000-0000-000000000003",
                        "value": "Free text"
                    },
                    {
                        "question_id": "0c210000-0000-0000-0000-000000000002",
                        "value": ["0c210000-0000-0000-0000-000000000006"]
                    }
                ]
            }'::jsonb
        )
        order by question_id
    $$,
    $$
        values
            ('0c210000-0000-0000-0000-000000000004'::uuid, '0c210000-0000-0000-0000-000000000001'::uuid),
            ('0c210000-0000-0000-0000-000000000006'::uuid, '0c210000-0000-0000-0000-000000000002'::uuid)
    $$,
    'Should return the selections of every answer in the payload'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
