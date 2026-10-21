-- Tests getting one response of an identified survey of a group event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(10);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set anonymousSurveyID 'a5e0001c-0000-0000-0000-000000000001'
\set communityID 'a5e0001c-0000-0000-0000-000000000002'
\set deletedEventID 'a5e0001c-0000-0000-0000-000000000003'
\set deletedEventSurveyID 'a5e0001c-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e0001c-0000-0000-0000-000000000005'
\set eventID 'a5e0001c-0000-0000-0000-000000000006'
\set firstUserID 'a5e0001c-0000-0000-0000-000000000007'
\set foreignGroupID 'a5e0001c-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e0001c-0000-0000-0000-000000000009'
\set groupID 'a5e0001c-0000-0000-0000-00000000000a'
\set nonRespondentUserID 'a5e0001c-0000-0000-0000-00000000000b'
\set otherEventID 'a5e0001c-0000-0000-0000-00000000000c'
\set questionID 'a5e0001c-0000-0000-0000-00000000000d'
\set secondUserID 'a5e0001c-0000-0000-0000-00000000000e'
\set surveyID 'a5e0001c-0000-0000-0000-00000000000f'
\set thirdUserID 'a5e0001c-0000-0000-0000-000000000010'
\set ticketTypeID 'a5e0001c-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- First respondent, matching the beta search
select fx_user(:'firstUserID', jsonb_build_object(
    'company', 'Beta Labs',
    'name', 'First Respondent',
    'username', 'first-respondent'
));

-- Attendee who did not answer the survey
select fx_user(:'nonRespondentUserID', jsonb_build_object('username', 'non-respondent'));

-- Second respondent, not matching the beta search
select fx_user(:'secondUserID', jsonb_build_object(
    'name', 'Second Respondent',
    'username', 'second-respondent'
));

-- Third respondent, matching the beta search
select fx_user(:'thirdUserID', jsonb_build_object(
    'name', 'Third Respondent',
    'title', 'Beta Tester',
    'username', 'third-respondent'
));

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

-- Identified survey with one free-text question
insert into event_survey (event_survey_id, anonymous, event_id, questions, title)
values (
    :'surveyID',
    false,
    :'eventID',
    jsonb_build_array(jsonb_build_object(
        'id', :'questionID',
        'kind', 'free-text',
        'options', '[]'::jsonb,
        'prompt', 'Comments',
        'required', false
    )),
    'Identified survey'
);

-- Ticket type of the event owning the surveys
select fx_event_ticket_type(:'ticketTypeID', :'eventID');

-- Completed VIP purchase of the first respondent
insert into event_purchase (
    amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    :'eventID',
    :'ticketTypeID',
    'completed',
    'VIP',
    :'firstUserID'
);

-- Edited response of the first respondent, created first
insert into event_survey_response (answers, created_at, event_survey_id, user_id, updated_at)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'questionID', 'value', 'Great talks')
    )),
    '2025-01-02 09:00:00+00',
    :'surveyID',
    :'firstUserID',
    '2025-01-02 09:30:00+00'
);

-- Response of the second respondent without answers, created second
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values ('{"answers": []}', '2025-01-02 09:01:00+00', :'surveyID', :'secondUserID');

-- Response of the third respondent, created last
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    jsonb_build_object('answers', jsonb_build_array(
        jsonb_build_object('question_id', :'questionID', 'value', 'More breaks')
    )),
    '2025-01-02 09:02:00+00',
    :'surveyID',
    :'thirdUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should leave the missing neighbors of the first and last respondents empty
select is(
    (
        select jsonb_build_object(
            'first', jsonb_build_object(
                'next_user_id', first_response->'next_user_id',
                'position', first_response->'position',
                'previous_user_id', first_response->'previous_user_id'
            ),
            'last', jsonb_build_object(
                'next_user_id', last_response->'next_user_id',
                'position', last_response->'position',
                'previous_user_id', last_response->'previous_user_id'
            )
        )
        from (
            select
                get_event_survey_response(
                    :'groupID'::uuid,
                    :'eventID'::uuid,
                    :'surveyID'::uuid,
                    :'firstUserID'::uuid,
                    '{}'::jsonb
                )::jsonb as first_response,
                get_event_survey_response(
                    :'groupID'::uuid,
                    :'eventID'::uuid,
                    :'surveyID'::uuid,
                    :'thirdUserID'::uuid,
                    '{}'::jsonb
                )::jsonb as last_response
        ) responses
    ),
    jsonb_build_object(
        'first', jsonb_build_object(
            'next_user_id', :'secondUserID'::uuid,
            'position', 1,
            'previous_user_id', null
        ),
        'last', jsonb_build_object(
            'next_user_id', null,
            'position', 3,
            'previous_user_id', :'secondUserID'::uuid
        )
    ),
    'Should leave the missing neighbors of the first and last respondents empty'
);

-- Should navigate among the respondents matching the search
select is(
    (
        select jsonb_build_object(
            'next_user_id', response->'next_user_id',
            'position', response->'position',
            'previous_user_id', response->'previous_user_id',
            'total', response->'total'
        )
        from (
            select get_event_survey_response(
                :'groupID'::uuid,
                :'eventID'::uuid,
                :'surveyID'::uuid,
                :'thirdUserID'::uuid,
                '{"ts_query": "beta"}'::jsonb
            )::jsonb as response
        ) result
    ),
    jsonb_build_object(
        'next_user_id', null,
        'position', 2,
        'previous_user_id', :'firstUserID'::uuid,
        'total', 2
    ),
    'Should navigate among the respondents matching the search'
);

-- Should reject anonymous surveys
select throws_ok(
    format(
        $$select get_event_survey_response(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{}'::jsonb)$$,
        :'groupID', :'eventID', :'anonymousSurveyID', :'firstUserID'
    ),
    'OCG01',
    'responses of anonymous surveys cannot be viewed',
    'Should reject anonymous surveys'
);

-- Should return null for deleted events
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'deletedEventID'::uuid,
        :'deletedEventSurveyID'::uuid,
        :'firstUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for deleted events'
);

-- Should return null for respondents not matching the search
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'secondUserID'::uuid,
        '{"ts_query": "beta"}'::jsonb
    )::jsonb,
    null,
    'Should return null for respondents not matching the search'
);

-- Should return null for surveys of another event
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'otherEventID'::uuid,
        :'surveyID'::uuid,
        :'firstUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for surveys of another event'
);

-- Should return null for surveys of another group
select is(
    get_event_survey_response(
        :'foreignGroupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'firstUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for surveys of another group'
);

-- Should return null for users without a response
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'nonRespondentUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    null,
    'Should return null for users without a response'
);

-- Should return the edited response of a respondent with a ticket
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'firstUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'answered_questions_count', 1,
        'answers', jsonb_build_object('answers', jsonb_build_array(
            jsonb_build_object('question_id', :'questionID', 'value', 'Great talks')
        )),
        'created_at', 1735808400,
        'user', jsonb_build_object(
            'user_id', :'firstUserID'::uuid,
            'username', 'first-respondent',

            'company', 'Beta Labs',
            'name', 'First Respondent'
        ),

        'ticket_title', 'VIP',
        'updated_at', 1735810200,

        'next_user_id', :'secondUserID'::uuid,
        'position', 1,
        'previous_user_id', null,
        'total', 3
    ),
    'Should return the edited response of a respondent with a ticket'
);

-- Should return the response with its neighbors among all respondents
select is(
    get_event_survey_response(
        :'groupID'::uuid,
        :'eventID'::uuid,
        :'surveyID'::uuid,
        :'secondUserID'::uuid,
        '{}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'answered_questions_count', 0,
        'answers', '{"answers": []}'::jsonb,
        'created_at', 1735808460,
        'user', jsonb_build_object(
            'user_id', :'secondUserID'::uuid,
            'username', 'second-respondent',

            'name', 'Second Respondent'
        ),

        'ticket_title', null,
        'updated_at', null,

        'next_user_id', :'thirdUserID'::uuid,
        'position', 2,
        'previous_user_id', :'firstUserID'::uuid,
        'total', 3
    ),
    'Should return the response with its neighbors among all respondents'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
