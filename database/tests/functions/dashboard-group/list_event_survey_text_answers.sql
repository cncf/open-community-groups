-- Tests paging and searching the free-text answers of surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00018-0000-0000-0000-000000000001'
\set deletedEventID 'a5e00018-0000-0000-0000-000000000002'
\set deletedEventSurveyID 'a5e00018-0000-0000-0000-000000000003'
\set eventCategoryID 'a5e00018-0000-0000-0000-000000000004'
\set eventID 'a5e00018-0000-0000-0000-000000000005'
\set feedbackQuestionID 'a5e00018-0000-0000-0000-000000000006'
\set foreignGroupID 'a5e00018-0000-0000-0000-000000000007'
\set goodOptionID 'a5e00018-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e00018-0000-0000-0000-000000000009'
\set groupID 'a5e00018-0000-0000-0000-00000000000a'
\set missingQuestionID 'a5e00018-0000-0000-0000-00000000000b'
\set otherEventID 'a5e00018-0000-0000-0000-00000000000e'
\set ratingQuestionID 'a5e00018-0000-0000-0000-00000000000c'
\set surveyID 'a5e00018-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Fifty-six respondents numbered 101 to 156
select fx_user(format('a5e00018-0000-0000-0000-000000000%s', n)::uuid)
from generate_series(101, 156) as n;

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that does not own the surveyed event
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Deleted event whose survey is hidden
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', '2025-01-01 10:00:00+00'
));

-- Event owning the survey
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Other event of the group
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Survey of the deleted event with the same free-text question
insert into event_survey (event_survey_id, event_id, questions, title)
values (
    :'deletedEventSurveyID',
    :'deletedEventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'feedbackQuestionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'Deleted event survey'
);

-- Ready anonymous survey with a single-select and a free-text question
insert into event_survey (event_survey_id, anonymous, event_id, questions, status, title, first_response_at)
values (
    :'surveyID',
    true,
    :'eventID',
    jsonb_build_array(
        jsonb_build_object(
            'id', :'ratingQuestionID'::uuid,
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'goodOptionID'::uuid, 'label', 'Good')
            ),
            'prompt', 'Rating',
            'required', false
        ),
        jsonb_build_object(
            'id', :'feedbackQuestionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )
    ),
    'ready',
    'Text answers survey',
    '2025-01-02 10:00:00+00'
);

-- Responses 101 to 156, one minute apart, answering "Answer 001" to
-- "Answer 055" and a blank answer from 156, all rating the event good
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
select
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'ratingQuestionID'::uuid, 'value', :'goodOptionID'::uuid),
        jsonb_build_object(
            'question_id', :'feedbackQuestionID'::uuid,
            'value', case when n <= 155 then 'Answer ' || lpad((n - 100)::text, 3, '0') else ' ' end
        )
    )),
    '2025-01-02 10:00:00+00'::timestamptz + make_interval(mins => n - 100),
    :'surveyID'::uuid,
    format('a5e00018-0000-0000-0000-000000000%s', n)::uuid
from generate_series(101, 156) as n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cap the page size at 50
select is(
    (
        select jsonb_build_object(
            'answers', jsonb_array_length(page->'answers'),
            'last', page->'answers'->49,
            'total', page->'total'
        )
        from (
            select list_event_survey_text_answers(
                :'groupID'::uuid,
                :'eventID'::uuid,
                :'surveyID'::uuid,
                :'feedbackQuestionID'::uuid,
                '{"limit": 100}'::jsonb
            )::jsonb as page
        ) result
    ),
    '{"answers": 50, "last": "Answer 050", "total": 55}'::jsonb,
    'Should cap the page size at 50'
);

-- Should default to pages of 10 plain answers
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'answers', jsonb_build_array(
            'Answer 001',
            'Answer 002',
            'Answer 003',
            'Answer 004',
            'Answer 005',
            'Answer 006',
            'Answer 007',
            'Answer 008',
            'Answer 009',
            'Answer 010'
        ),
        'position', 2,
        'prompt', 'Feedback',
        'total', 55
    ),
    'Should default to pages of 10 plain answers'
);

-- Should match search wildcards literally
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{"ts_query": "Answer 0%5"}'::jsonb
    )::jsonb,
    '{"answers": [], "position": 2, "prompt": "Feedback", "total": 0}'::jsonb,
    'Should match search wildcards literally'
);

-- Should page answers by offset in response creation order
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{"limit": 2, "offset": 10}'::jsonb
    )::jsonb,
    '{"answers": ["Answer 011", "Answer 012"], "position": 2, "prompt": "Feedback", "total": 55}'::jsonb,
    'Should page answers by offset in response creation order'
);

-- Should page the answers matching the search case-insensitively
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{"limit": 3, "offset": 1, "ts_query": "  aNSWER 01 "}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'answers', jsonb_build_array('Answer 011', 'Answer 012', 'Answer 013'),
        'position', 2,
        'prompt', 'Feedback',
        'total', 10
    ),
    'Should page the answers matching the search case-insensitively'
);

-- Should return null for deleted events
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'deletedEventID'::uuid,
        :'deletedEventSurveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for deleted events'
);

-- Should return null for select questions
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'ratingQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for select questions'
);

-- Should return null for surveys of another event
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'otherEventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for surveys of another event'
);

-- Should return null for surveys of another group
select is(
    list_event_survey_text_answers(
        :'foreignGroupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'feedbackQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- Should return null for unknown questions
select is(
    list_event_survey_text_answers(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'missingQuestionID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for unknown questions'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
