-- Tests aggregating the results of surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set badOptionID 'a5e00017-0000-0000-0000-000000000001'
\set communityID 'a5e00017-0000-0000-0000-000000000002'
\set emptySurveyID 'a5e00017-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00017-0000-0000-0000-000000000006'
\set eventID 'a5e00017-0000-0000-0000-000000000007'
\set feedbackQuestionID 'a5e00017-0000-0000-0000-000000000008'
\set foreignGroupID 'a5e00017-0000-0000-0000-000000000009'
\set goodOptionID 'a5e00017-0000-0000-0000-00000000000a'
\set groupCategoryID 'a5e00017-0000-0000-0000-00000000000b'
\set groupID 'a5e00017-0000-0000-0000-00000000000c'
\set noQuestionsSurveyID 'a5e00017-0000-0000-0000-000000000012'
\set ratingQuestionID 'a5e00017-0000-0000-0000-00000000000d'
\set rustOptionID 'a5e00017-0000-0000-0000-00000000000e'
\set sqlOptionID 'a5e00017-0000-0000-0000-00000000000f'
\set surveyID 'a5e00017-0000-0000-0000-000000000010'
\set topicsQuestionID 'a5e00017-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Twelve respondents numbered 101 to 112
select fx_user(format('a5e00017-0000-0000-0000-000000000%s', n)::uuid)
from generate_series(101, 112) as n;

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that does not own the surveyed event
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event that already ended
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Ready survey without responses
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (
    :'emptySurveyID',
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
            'required', true
        )
    ),
    'ready',
    'Empty survey'
);

-- Ready survey without questions
insert into event_survey (event_survey_id, event_id, status, title)
values (:'noQuestionsSurveyID', :'eventID', 'ready', 'No questions survey');

-- Ready survey with select and free-text questions
insert into event_survey (event_survey_id, event_id, questions, status, title, first_response_at)
values (
    :'surveyID',
    :'eventID',
    jsonb_build_array(
        jsonb_build_object(
            'id', :'ratingQuestionID'::uuid,
            'kind', 'single-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'goodOptionID'::uuid, 'label', 'Good'),
                jsonb_build_object('id', :'badOptionID'::uuid, 'label', 'Bad')
            ),
            'prompt', 'Rating',
            'required', true
        ),
        jsonb_build_object(
            'id', :'feedbackQuestionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        ),
        jsonb_build_object(
            'id', :'topicsQuestionID'::uuid,
            'kind', 'multi-select',
            'options', jsonb_build_array(
                jsonb_build_object('id', :'rustOptionID'::uuid, 'label', 'Rust'),
                jsonb_build_object('id', :'sqlOptionID'::uuid, 'label', 'SQL')
            ),
            'prompt', 'Topics',
            'required', false
        )
    ),
    'ready',
    'Results survey',
    '2025-01-02 10:00:00+00'
);

-- Responses 101 to 112, one minute apart: ratings 101-108 good and 109-112
-- bad; feedback "Answer 01" to "Answer 11" and a blank one from 112; topics
-- Rust and SQL from 101-103, Rust only from 104-106 and none from the rest
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
select
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object(
            'question_id', :'ratingQuestionID'::uuid,
            'value', case when n <= 108 then :'goodOptionID'::uuid else :'badOptionID'::uuid end
        ),
        jsonb_build_object(
            'question_id', :'feedbackQuestionID'::uuid,
            'value', case when n <= 111 then 'Answer ' || lpad((n - 100)::text, 2, '0') else '  ' end
        )
    ) || case
        when n <= 103 then jsonb_build_array(jsonb_build_object(
            'question_id', :'topicsQuestionID'::uuid,
            'value', jsonb_build_array(:'rustOptionID'::uuid, :'sqlOptionID'::uuid)
        ))
        when n <= 106 then jsonb_build_array(jsonb_build_object(
            'question_id', :'topicsQuestionID'::uuid,
            'value', jsonb_build_array(:'rustOptionID'::uuid)
        ))
        else '[]'::jsonb
    end),
    '2025-01-02 10:00:00+00'::timestamptz + make_interval(mins => n - 100),
    :'surveyID'::uuid,
    format('a5e00017-0000-0000-0000-000000000%s', n)::uuid
from generate_series(101, 112) as n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should never return respondent identities
select ok(
    not exists (
        select 1
        from event_survey_response r
        where position(
            r.user_id::text
            in get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb::text
        ) > 0
    ),
    'Should never return respondent identities'
);

-- Should report empty results for surveys without responses
select is(
    get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, :'emptySurveyID'::uuid)::jsonb->'questions',
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'position', 1,
            'prompt', 'Rating',
            'question_id', :'ratingQuestionID'::uuid,
            'required', false,

            'breakdown', jsonb_build_object(
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('count', 0, 'label', 'Good', 'option_id', :'goodOptionID'::uuid)
                ),
                'position', 1,
                'prompt', 'Rating',
                'question_id', :'ratingQuestionID'::uuid,
                'respondents', 0,
                'selections', 0
            ),
            'text_answers', null
        ),
        jsonb_build_object(
            'kind', 'free-text',
            'position', 2,
            'prompt', 'Feedback',
            'question_id', :'feedbackQuestionID'::uuid,
            'required', true,

            'breakdown', null,
            'text_answers', jsonb_build_object('answers', '[]'::jsonb, 'total', 0)
        )
    ),
    'Should report empty results for surveys without responses'
);

-- Should return an empty questions list for surveys without questions
select is(
    get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, :'noQuestionsSurveyID'::uuid)::jsonb->'questions',
    '[]'::jsonb,
    'Should return an empty questions list for surveys without questions'
);

-- Should return null for surveys of another group
select is(
    get_event_survey_results(:'foreignGroupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- Should return null without a survey id
select is(
    get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, null)::jsonb,
    null,
    'Should return null without a survey id'
);

-- Should return the questions in order with breakdowns and the first text answers
select is(
    get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb->'questions',
    jsonb_build_array(
        jsonb_build_object(
            'kind', 'single-select',
            'position', 1,
            'prompt', 'Rating',
            'question_id', :'ratingQuestionID'::uuid,
            'required', true,

            'breakdown', jsonb_build_object(
                'kind', 'single-select',
                'options', jsonb_build_array(
                    jsonb_build_object('count', 8, 'label', 'Good', 'option_id', :'goodOptionID'::uuid),
                    jsonb_build_object('count', 4, 'label', 'Bad', 'option_id', :'badOptionID'::uuid)
                ),
                'position', 1,
                'prompt', 'Rating',
                'question_id', :'ratingQuestionID'::uuid,
                'respondents', 12,
                'selections', 12
            ),
            'text_answers', null
        ),
        jsonb_build_object(
            'kind', 'free-text',
            'position', 2,
            'prompt', 'Feedback',
            'question_id', :'feedbackQuestionID'::uuid,
            'required', false,

            'breakdown', null,
            'text_answers', jsonb_build_object(
                'answers', jsonb_build_array(
                    'Answer 01',
                    'Answer 02',
                    'Answer 03',
                    'Answer 04',
                    'Answer 05',
                    'Answer 06',
                    'Answer 07',
                    'Answer 08',
                    'Answer 09',
                    'Answer 10'
                ),
                'total', 11
            )
        ),
        jsonb_build_object(
            'kind', 'multi-select',
            'position', 3,
            'prompt', 'Topics',
            'question_id', :'topicsQuestionID'::uuid,
            'required', false,

            'breakdown', jsonb_build_object(
                'kind', 'multi-select',
                'options', jsonb_build_array(
                    jsonb_build_object('count', 6, 'label', 'Rust', 'option_id', :'rustOptionID'::uuid),
                    jsonb_build_object('count', 3, 'label', 'SQL', 'option_id', :'sqlOptionID'::uuid)
                ),
                'position', 3,
                'prompt', 'Topics',
                'question_id', :'topicsQuestionID'::uuid,
                'respondents', 6,
                'selections', 9
            ),
            'text_answers', null
        )
    ),
    'Should return the questions in order with breakdowns and the first text answers'
);

-- Should return the survey summary
select is(
    get_event_survey_results(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid)::jsonb->'survey',
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'surveyID'
    ),
    'Should return the survey summary'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
