-- Tests paging the responses of identified surveys of group events.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set anonymousSurveyID 'a5e00019-0000-0000-0000-000000000001'
\set communityID 'a5e00019-0000-0000-0000-000000000002'
\set deletedEventID 'a5e00019-0000-0000-0000-000000000003'
\set deletedEventSurveyID 'a5e00019-0000-0000-0000-000000000004'
\set detailedUserID 'a5e00019-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00019-0000-0000-0000-000000000006'
\set eventID 'a5e00019-0000-0000-0000-000000000007'
\set foreignGroupID 'a5e00019-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e00019-0000-0000-0000-000000000009'
\set groupID 'a5e00019-0000-0000-0000-00000000000a'
\set otherEventID 'a5e00019-0000-0000-0000-00000000000d'
\set plainUserID 'a5e00019-0000-0000-0000-00000000000b'
\set surveyID 'a5e00019-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Respondent with every profile detail
select fx_user(:'detailedUserID', jsonb_build_object(
    'company', 'Example Corp',
    'name', 'Detailed Respondent',
    'photo_url', 'https://example.test/detailed.png',
    'title', 'Engineer',
    'username', 'detailed-respondent'
));

-- Respondent without optional profile details
select fx_user(:'plainUserID', jsonb_build_object('username', 'plain-respondent'));

-- Fifty-three more respondents numbered 101 to 153
select fx_user(format('a5e00019-0000-0000-0000-000000000%s', n)::uuid)
from generate_series(101, 153) as n;

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

-- Anonymous survey whose respondents stay hidden
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'anonymousSurveyID', true, :'eventID', 'Anonymous survey');

-- Identified survey of the deleted event
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'deletedEventSurveyID', false, :'deletedEventID', 'Deleted event survey');

-- Identified survey with responses
insert into event_survey (event_survey_id, anonymous, event_id, title)
values (:'surveyID', false, :'eventID', 'Identified survey');

-- Edited response from the detailed respondent, created first
insert into event_survey_response (answers, created_at, event_survey_id, user_id, updated_at)
values ('{"answers": []}', '2025-01-02 09:00:00+00', :'surveyID', :'detailedUserID', '2025-01-02 09:30:00+00');

-- Response from the plain respondent, created second
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values ('{"answers": []}', '2025-01-02 09:01:00+00', :'surveyID', :'plainUserID');

-- Responses 101 to 153, one minute apart after the named ones
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
select
    '{"answers": []}'::jsonb,
    '2025-01-02 10:00:00+00'::timestamptz + make_interval(mins => n - 100),
    :'surveyID'::uuid,
    format('a5e00019-0000-0000-0000-000000000%s', n)::uuid
from generate_series(101, 153) as n;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should cap the page size at 50
select is(
    (
        select jsonb_build_object(
            'responses', jsonb_array_length(page->'responses'),
            'total', page->'total'
        )
        from (
            select list_event_survey_responses(
                :'groupID'::uuid,
                :'eventID'::uuid,
                :'surveyID'::uuid,
                '{"limit": 100}'::jsonb
            )::jsonb as page
        ) result
    ),
    '{"responses": 50, "total": 55}'::jsonb,
    'Should cap the page size at 50'
);

-- Should default to pages of 20
select is(
    jsonb_array_length(
        list_event_survey_responses(:'groupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid, '{}'::jsonb)::jsonb->'responses'
    ),
    20,
    'Should default to pages of 20'
);

-- Should list responses in creation order with respondent details
select is(
    list_event_survey_responses(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        '{"limit": 2}'::jsonb
    )::jsonb->'responses',
    jsonb_build_array(
        jsonb_build_object(
            'answers', '{"answers": []}'::jsonb,
            'created_at', 1735808400,
            'user', jsonb_build_object(
                'user_id', :'detailedUserID'::uuid,
                'username', 'detailed-respondent',

                'company', 'Example Corp',
                'name', 'Detailed Respondent',
                'photo_url', 'https://example.test/detailed.png',
                'title', 'Engineer'
            ),

            'updated_at', 1735810200
        ),
        jsonb_build_object(
            'answers', '{"answers": []}'::jsonb,
            'created_at', 1735808460,
            'user', jsonb_build_object(
                'user_id', :'plainUserID'::uuid,
                'username', 'plain-respondent'
            ),

            'updated_at', null
        )
    ),
    'Should list responses in creation order with respondent details'
);

-- Should page responses by offset
select is(
    list_event_survey_responses(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        '{"limit": 1, "offset": 2}'::jsonb
    )::jsonb#>>'{responses,0,user,user_id}',
    'a5e00019-0000-0000-0000-000000000101',
    'Should page responses by offset'
);

-- Should reject anonymous surveys
select throws_ok(
    format(
        $$select list_event_survey_responses(%L::uuid, %L::uuid, %L::uuid, '{}'::jsonb)::jsonb$$,
        :'groupID', :'eventID', :'anonymousSurveyID'
    ),
    'OCG01',
    'responses of anonymous surveys cannot be listed',
    'Should reject anonymous surveys'
);

-- Should return an empty page past the last response
select is(
    list_event_survey_responses(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        '{"limit": 10, "offset": 55}'::jsonb
    )::jsonb,
    '{"responses": [], "total": 55}'::jsonb,
    'Should return an empty page past the last response'
);

-- Should return null for deleted events
select is(
    list_event_survey_responses(:'groupID'::uuid, :'deletedEventID'::uuid, :'deletedEventSurveyID'::uuid, '{}'::jsonb)::jsonb,
    null,
    'Should return null for deleted events'
);

-- Should return null for surveys of another event
select is(
    list_event_survey_responses(:'groupID'::uuid, :'otherEventID'::uuid, :'surveyID'::uuid, '{}'::jsonb)::jsonb,
    null,
    'Should return null for surveys of another event'
);

-- Should return null for surveys of another group
select is(
    list_event_survey_responses(:'foreignGroupID'::uuid, :'eventID'::uuid, :'surveyID'::uuid, '{}'::jsonb)::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
