-- Tests checking whether a questionnaire answer value answers its question.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept non-blank text
select ok(
    questionnaire_answer_has_value('" Answer "'::jsonb),
    'Should accept non-blank text'
);

-- Should accept selections with at least one option
select ok(
    questionnaire_answer_has_value('["option"]'::jsonb),
    'Should accept selections with at least one option'
);

-- Should reject blank text and empty selections
select results_eq(
    $$
        select questionnaire_answer_has_value(value)
        from (values ('""'::jsonb), ('"   "'::jsonb), ('[]'::jsonb)) as answer(value)
    $$,
    $$ values (false), (false), (false) $$,
    'Should reject blank text and empty selections'
);

-- Should reject missing and non-answer values
select results_eq(
    $$
        select questionnaire_answer_has_value(value)
        from (
            values
                (null::jsonb),
                ('null'::jsonb),
                ('1'::jsonb),
                ('true'::jsonb),
                ('{"id": "option"}'::jsonb)
        ) as answer(value)
    $$,
    $$ values (false), (false), (false), (false), (false) $$,
    'Should reject missing and non-answer values'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
