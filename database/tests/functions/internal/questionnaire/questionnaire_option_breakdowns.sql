-- Tests building the option breakdowns of questionnaire select questions.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set option1ID '0c220000-0000-0000-0000-000000000001'
\set option2ID '0c220000-0000-0000-0000-000000000002'
\set option3ID '0c220000-0000-0000-0000-000000000003'
\set option4ID '0c220000-0000-0000-0000-000000000004'
\set optionRemovedID '0c220000-0000-0000-0000-000000000005'
\set questionFreeTextID '0c220000-0000-0000-0000-000000000006'
\set questionMultiID '0c220000-0000-0000-0000-000000000007'
\set questionSingleID '0c220000-0000-0000-0000-000000000008'
\set questionUnknownID '0c220000-0000-0000-0000-000000000009'
\set respondent1ID '0c220000-0000-0000-0000-00000000000a'
\set respondent2ID '0c220000-0000-0000-0000-00000000000b'
\set respondent3ID '0c220000-0000-0000-0000-00000000000c'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should break down select questions by their current options with positions
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionFreeTextID',
                'kind', 'free-text',
                'options', jsonb_build_array(),
                'prompt', 'Comments',
                'required', false
            ),
            jsonb_build_object(
                'id', :'questionSingleID',
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option2ID', 'label', 'Ops'),
                    jsonb_build_object('id', :'option1ID', 'label', 'Dev')
                ),
                'prompt', 'Role',
                'required', false
            ),
            jsonb_build_object(
                'id', :'questionMultiID',
                'kind', 'multi-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option3ID', 'label', 'AI'),
                    jsonb_build_object('id', :'option4ID', 'label', 'Cloud')
                ),
                'prompt', 'Interests',
                'required', false
            )
        ),
        jsonb_build_array(
            jsonb_build_object('o', :'option1ID', 'q', :'questionSingleID', 'r', :'respondent1ID'),
            jsonb_build_object('o', :'option1ID', 'q', :'questionSingleID', 'r', :'respondent2ID'),
            jsonb_build_object('o', :'option2ID', 'q', :'questionSingleID', 'r', :'respondent3ID'),
            jsonb_build_object('o', :'option3ID', 'q', :'questionMultiID', 'r', :'respondent1ID'),
            jsonb_build_object('o', :'option4ID', 'q', :'questionMultiID', 'r', :'respondent1ID'),
            jsonb_build_object('o', :'option3ID', 'q', :'questionMultiID', 'r', :'respondent2ID')
        )
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 1, 'label', 'Ops', 'option_id', :'option2ID'),
                jsonb_build_object('count', 2, 'label', 'Dev', 'option_id', :'option1ID')
            ),
            'position', 2,
            'prompt', 'Role',
            'question_id', :'questionSingleID',
            'respondents', 3,
            'selections', 3
        ),
        jsonb_build_object(
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 2, 'label', 'AI', 'option_id', :'option3ID'),
                jsonb_build_object('count', 1, 'label', 'Cloud', 'option_id', :'option4ID')
            ),
            'position', 3,
            'prompt', 'Interests',
            'question_id', :'questionMultiID',
            'respondents', 2,
            'selections', 3
        )
    ),
    'Should break down select questions by their current options with positions'
);

-- Should ignore selections of another question
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionSingleID',
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option1ID', 'label', 'Dev')
                ),
                'prompt', 'Role',
                'required', false
            ),
            jsonb_build_object(
                'id', :'questionMultiID',
                'kind', 'multi-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option3ID', 'label', 'AI')
                ),
                'prompt', 'Interests',
                'required', false
            )
        ),
        jsonb_build_array(
            jsonb_build_object('o', :'option1ID', 'q', :'questionMultiID', 'r', :'respondent1ID'),
            jsonb_build_object('o', :'option3ID', 'q', :'questionMultiID', 'r', :'respondent2ID')
        )
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 0, 'label', 'Dev', 'option_id', :'option1ID')
            ),
            'position', 1,
            'prompt', 'Role',
            'question_id', :'questionSingleID',
            'respondents', 0,
            'selections', 0
        ),
        jsonb_build_object(
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 1, 'label', 'AI', 'option_id', :'option3ID')
            ),
            'position', 2,
            'prompt', 'Interests',
            'question_id', :'questionMultiID',
            'respondents', 1,
            'selections', 1
        )
    ),
    'Should ignore selections of another question'
);

-- Should ignore selections of removed options and unknown questions
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionSingleID',
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option1ID', 'label', 'Dev')
                ),
                'prompt', 'Role',
                'required', false
            )
        ),
        jsonb_build_array(
            jsonb_build_object('o', :'optionRemovedID', 'q', :'questionSingleID', 'r', :'respondent1ID'),
            jsonb_build_object('o', :'option1ID', 'q', :'questionUnknownID', 'r', :'respondent2ID')
        )
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 0, 'label', 'Dev', 'option_id', :'option1ID')
            ),
            'position', 1,
            'prompt', 'Role',
            'question_id', :'questionSingleID',
            'respondents', 0,
            'selections', 0
        )
    ),
    'Should ignore selections of removed options and unknown questions'
);

-- Should report zero counts for options without selections
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionSingleID',
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option1ID', 'label', 'Dev'),
                    jsonb_build_object('id', :'option2ID', 'label', 'Ops')
                ),
                'prompt', 'Role',
                'required', false
            )
        ),
        jsonb_build_array(
            jsonb_build_object('o', :'option1ID', 'q', :'questionSingleID', 'r', :'respondent1ID')
        )
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 1, 'label', 'Dev', 'option_id', :'option1ID'),
                jsonb_build_object('count', 0, 'label', 'Ops', 'option_id', :'option2ID')
            ),
            'position', 1,
            'prompt', 'Role',
            'question_id', :'questionSingleID',
            'respondents', 1,
            'selections', 1
        )
    ),
    'Should report zero counts for options without selections'
);

-- Should return an empty array for questions that are not an array
select is(
    questionnaire_option_breakdowns(null, '[]'::jsonb)::jsonb,
    '[]'::jsonb,
    'Should return an empty array for questions that are not an array'
);

-- Should return an empty array without select questions
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionFreeTextID',
                'kind', 'free-text',
                'options', jsonb_build_array(),
                'prompt', 'Comments',
                'required', false
            )
        ),
        '[]'::jsonb
    )::jsonb,
    '[]'::jsonb,
    'Should return an empty array without select questions'
);

-- Should return zero counts for selections that are not an array
select is(
    questionnaire_option_breakdowns(
        jsonb_build_array(
            jsonb_build_object(
                'id', :'questionMultiID',
                'kind', 'multi-select',
                'options', jsonb_build_array(
                    jsonb_build_object('id', :'option3ID', 'label', 'AI')
                ),
                'prompt', 'Interests',
                'required', false
            )
        ),
        null
    )::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('count', 0, 'label', 'AI', 'option_id', :'option3ID')
            ),
            'position', 1,
            'prompt', 'Interests',
            'question_id', :'questionMultiID',
            'respondents', 0,
            'selections', 0
        )
    ),
    'Should return zero counts for selections that are not an array'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
