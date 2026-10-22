-- Tests exporting the responses of surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set anonymousSurveyID 'a5e0001a-0000-0000-0000-000000000001'
\set communityID 'a5e0001a-0000-0000-0000-000000000002'
\set deletedEventID 'a5e0001a-0000-0000-0000-000000000003'
\set deletedEventSurveyID 'a5e0001a-0000-0000-0000-000000000004'
\set detailedUserID 'a5e0001a-0000-0000-0000-000000000005'
\set emptySurveyID 'a5e0001a-0000-0000-0000-00000000000e'
\set eventCategoryID 'a5e0001a-0000-0000-0000-000000000006'
\set eventID 'a5e0001a-0000-0000-0000-000000000007'
\set foreignGroupID 'a5e0001a-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e0001a-0000-0000-0000-000000000009'
\set groupID 'a5e0001a-0000-0000-0000-00000000000a'
\set otherEventID 'a5e0001a-0000-0000-0000-00000000000f'
\set plainUserID 'a5e0001a-0000-0000-0000-00000000000b'
\set questionID 'a5e0001a-0000-0000-0000-00000000000c'
\set surveyID 'a5e0001a-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Respondent with every profile detail
select fx_user(:'detailedUserID', jsonb_build_object(
    'company', 'Example Corp',
    'name', 'Detailed Exporter',
    'photo_url', 'https://example.test/exporter.png',
    'title', 'Engineer',
    'username', 'detailed-exporter'
));

-- Respondent without optional profile details
select fx_user(:'plainUserID', jsonb_build_object('username', 'plain-exporter'));

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

-- Event owning the surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event of the same group that does not own the surveys
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Anonymous survey with one free-text question
insert into event_survey (event_survey_id, anonymous, event_id, questions, title)
values (
    :'anonymousSurveyID',
    true,
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID'::uuid,
        'kind', 'free-text',
        'prompt', 'Feedback',
        'required', false
    )),
    'Anonymous survey'
);

-- Identified survey of the deleted event
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'deletedEventSurveyID', false, :'deletedEventID', 'Deleted event survey');

-- Identified survey without responses
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'emptySurveyID', false, :'eventID', 'Empty survey');

-- Identified survey without questions
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'surveyID', false, :'eventID', 'Identified survey');

-- Anonymous survey response from the detailed respondent
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'questionID'::uuid, 'value', 'Great')
    )),
    '2025-01-02 09:00:00+00',
    :'anonymousSurveyID',
    :'detailedUserID'
);

-- Edited identified survey response from the detailed respondent, created first
insert into event_survey_response (answers, created_at, event_survey_id, user_id, updated_at)
values ('{"answers": []}', '2025-01-02 09:00:00+00', :'surveyID', :'detailedUserID', '2025-01-02 09:30:00+00');

-- Identified survey response from the plain respondent, created second
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values ('{"answers": []}', '2025-01-02 09:01:00+00', :'surveyID', :'plainUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should export anonymous surveys with dates and answers only
select is(
    get_event_survey_export(:'groupID'::uuid, :'eventID'::uuid, :'anonymousSurveyID'::uuid, 10, 1000)::jsonb,
    jsonb_build_object(
        'anonymous', true,
        'questions', jsonb_build_array(jsonb_build_object(
            'id', :'questionID'::uuid,
            'kind', 'free-text',
            'prompt', 'Feedback',
            'required', false
        )),
        'responses', jsonb_build_array(jsonb_build_object(
            'answers', jsonb_build_object('answers', jsonb_build_array(
                jsonb_build_object('question_id', :'questionID'::uuid, 'value', 'Great')
            )),
            'created_at', 1735808400,

            'updated_at', null
        )),
        'title', 'Anonymous survey'
    ),
    'Should export anonymous surveys with dates and answers only'
);

-- Should export identified surveys with respondent details at both bounds
select is(
    get_event_survey_export(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid, 2, 30)::jsonb,
    jsonb_build_object(
        'anonymous', false,
        'questions', '[]'::jsonb,
        'responses', jsonb_build_array(
            jsonb_build_object(
                'answers', '{"answers": []}'::jsonb,
                'created_at', 1735808400,
                'user', jsonb_build_object(
                    'username', 'detailed-exporter',

                    'company', 'Example Corp',
                    'name', 'Detailed Exporter',
                    'title', 'Engineer'
                ),

                'updated_at', 1735810200
            ),
            jsonb_build_object(
                'answers', '{"answers": []}'::jsonb,
                'created_at', 1735808460,
                'user', jsonb_build_object('username', 'plain-exporter'),

                'updated_at', null
            )
        ),
        'title', 'Identified survey'
    ),
    'Should export identified surveys with respondent details at both bounds'
);

-- Should export surveys without responses with an empty responses list
select is(
    get_event_survey_export(:'groupID'::uuid, :'eventID'::uuid, :'emptySurveyID'::uuid, 10, 1000)::jsonb,
    jsonb_build_object(
        'anonymous', false,
        'questions', '[]'::jsonb,
        'responses', '[]'::jsonb,
        'title', 'Empty survey'
    ),
    'Should export surveys without responses with an empty responses list'
);

-- Should reject exports above the answers size bound
select throws_ok(
    format(
        $$select get_event_survey_export(%L::uuid, %L::uuid, %L::uuid, 2, 29)::jsonb$$,
        :'groupID', :'eventID', :'surveyID'
    ),
    'OCG01',
    'survey export supports up to 2 responses and 29 bytes of answers; this survey has 2 responses and 30 bytes',
    'Should reject exports above the answers size bound'
);

-- Should reject exports above the responses bound
select throws_ok(
    format(
        $$select get_event_survey_export(%L::uuid, %L::uuid, %L::uuid, 1, 30)::jsonb$$,
        :'groupID', :'eventID', :'surveyID'
    ),
    'OCG01',
    'survey export supports up to 1 responses and 30 bytes of answers; this survey has 2 responses and 30 bytes',
    'Should reject exports above the responses bound'
);

-- Should return null for deleted events
select is(
    get_event_survey_export(:'groupID'::uuid, :'deletedEventID'::uuid, :'deletedEventSurveyID'::uuid, 10, 1000)::jsonb,
    null,
    'Should return null for deleted events'
);

-- Should return null for surveys of another event
select is(
    get_event_survey_export(:'groupID'::uuid, :'otherEventID'::uuid, :'surveyID'::uuid, 10, 1000)::jsonb,
    null,
    'Should return null for surveys of another event'
);

-- Should return null for surveys of another group
select is(
    get_event_survey_export(:'foreignGroupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid, 10, 1000)::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
