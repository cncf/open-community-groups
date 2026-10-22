-- Tests listing the answers of a questionnaire answers payload.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return every answer of the payload in order
select results_eq(
    $$
        select answer.value
        from questionnaire_answer_entries(
            '{
                "answers": [
                    {"question_id": "first", "value": "Text"},
                    {"question_id": "second", "value": []},
                    "not-an-object"
                ]
            }'::jsonb
        ) with ordinality as answer(value, position)
        order by answer.position
    $$,
    $$
        values
            ('{"question_id": "first", "value": "Text"}'::jsonb),
            ('{"question_id": "second", "value": []}'::jsonb),
            ('"not-an-object"'::jsonb)
    $$,
    'Should return every answer of the payload in order'
);

-- Should return nothing for payloads without an answers array
select is_empty(
    $$
        select * from questionnaire_answer_entries(null)
        union all
        select * from questionnaire_answer_entries('{}'::jsonb)
        union all
        select * from questionnaire_answer_entries('{"answers": {}}'::jsonb)
        union all
        select * from questionnaire_answer_entries('{"answers": "text"}'::jsonb)
        union all
        select * from questionnaire_answer_entries('[]'::jsonb)
    $$,
    'Should return nothing for payloads without an answers array'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
