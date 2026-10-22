-- Tests submitting a user's answers to a survey of a public event from the
-- dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00033-0000-0000-0000-000000000001'
\set canceledEventSurveyID 'a5e00033-0000-0000-0000-000000000002'
\set checkedInSurveyID 'a5e00033-0000-0000-0000-000000000003'
\set closedSurveyID 'a5e00033-0000-0000-0000-000000000004'
\set communityID 'a5e00033-0000-0000-0000-000000000005'
\set editedSurveyID 'a5e00033-0000-0000-0000-00000000000a'
\set eventCategoryID 'a5e00033-0000-0000-0000-00000000000b'
\set eventID 'a5e00033-0000-0000-0000-00000000000c'
\set groupCategoryID 'a5e00033-0000-0000-0000-00000000000d'
\set groupID 'a5e00033-0000-0000-0000-00000000000e'
\set invalidAnswersSurveyID 'a5e00033-0000-0000-0000-000000000018'
\set lockedSurveyID 'a5e00033-0000-0000-0000-000000000025'
\set newResponseSurveyID 'a5e00033-0000-0000-0000-000000000019'
\set respondentID 'a5e00033-0000-0000-0000-00000000001c'
\set secondRespondentID 'a5e00033-0000-0000-0000-000000000028'
\set staleSurveyID 'a5e00033-0000-0000-0000-00000000001e'

-- Answers to the required free-text question of every survey
\set answers '{"answers": [{"question_id": "a5e00033-0000-0000-0000-000000000021", "value": "Great"}]}'

-- Required free-text question shared by every survey
\set questions '[{"id": "a5e00033-0000-0000-0000-000000000021", "kind": "free-text", "prompt": "Feedback", "required": true}]'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Confirmed attendee answering the surveys
select fx_user(:'respondentID');

-- Confirmed attendee answering after the first response
select fx_user(:'secondRespondentID');

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group hosting the public surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Canceled published event that already ended
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Published ended event hosting the answered surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '2 days',
    'published', true,
    'starts_at', current_timestamp - interval '2 days 2 hours'
));

-- Confirmed attendee who did not check in
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'eventID', 'confirmed', :'respondentID');

-- Confirmed attendee answering the survey that already has a response
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'eventID', 'confirmed', :'secondRespondentID');

-- Ready survey of the canceled event
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (:'canceledEventSurveyID', :'canceledEventID', :'questions'::jsonb, 'ready', 'Canceled event survey');

-- Open survey limited to checked-in attendees
insert into event_survey (event_survey_id, audience, event_id, questions, status, title)
values (:'checkedInSurveyID', 'checked-in', :'eventID', :'questions'::jsonb, 'ready', 'Checked-in survey');

-- Ready survey closed manually
insert into event_survey (event_survey_id, event_id, questions, status, title, closed_at)
values (
    :'closedSurveyID',
    :'eventID',
    :'questions'::jsonb,
    'ready',
    'Closed survey',
    current_timestamp - interval '1 hour'
);

-- Open survey the attendee answered before
insert into event_survey (event_survey_id, event_id, questions, status, title, first_response_at)
values (
    :'editedSurveyID',
    :'eventID',
    :'questions'::jsonb,
    'ready',
    'Edited survey',
    current_timestamp - interval '1 day'
);

-- Open survey receiving invalid answers
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (:'invalidAnswersSurveyID', :'eventID', :'questions'::jsonb, 'ready', 'Invalid answers survey');

-- Open survey another attendee answered first
insert into event_survey (event_survey_id, event_id, questions, status, title, first_response_at)
values (
    :'lockedSurveyID',
    :'eventID',
    :'questions'::jsonb,
    'ready',
    'Locked survey',
    current_timestamp - interval '1 day'
);

-- Open survey without responses
insert into event_survey (event_survey_id, event_id, questions, status, title)
values (:'newResponseSurveyID', :'eventID', :'questions'::jsonb, 'ready', 'New response survey');

-- Open survey changed after the attendee loaded it
insert into event_survey (event_survey_id, event_id, questions, revision, status, title)
values (:'staleSurveyID', :'eventID', :'questions'::jsonb, 2, 'ready', 'Stale survey');

-- Earlier response the attendee edits
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    '{"answers": [{"question_id": "a5e00033-0000-0000-0000-000000000021", "value": "Fine"}]}'::jsonb,
    current_timestamp - interval '1 day',
    :'editedSurveyID',
    :'respondentID'
);

-- First response to the locked survey
insert into event_survey_response (answers, created_at, event_survey_id, user_id)
values (
    '{"answers": [{"question_id": "a5e00033-0000-0000-0000-000000000021", "value": "Fine"}]}'::jsonb,
    current_timestamp - interval '1 day',
    :'lockedSurveyID',
    :'respondentID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep the creation time and first response time when a response is edited
select lives_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'editedSurveyID', :'respondentID', :'answers'
    ),
    'Should keep the creation time and first response time when a response is edited'
);
select is(
    (
        select jsonb_build_object(
            'answers', r.answers,
            'created_at', r.created_at,
            'first_response_at', s.first_response_at,
            'updated_at', r.updated_at
        )
        from event_survey_response r
        join event_survey s on s.event_survey_id = r.event_survey_id
        where r.event_survey_id = :'editedSurveyID'
        and r.user_id = :'respondentID'
    ),
    jsonb_build_object(
        'answers', :'answers'::jsonb,
        'created_at', current_timestamp - interval '1 day',
        'first_response_at', current_timestamp - interval '1 day',
        'updated_at', current_timestamp
    ),
    'Should replace the answers of the edited response'
);

-- Should keep the first response time when another user answers
select lives_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'lockedSurveyID', :'secondRespondentID', :'answers'
    ),
    'Should keep the first response time when another user answers'
);
select is(
    (
        select jsonb_build_object(
            'first_response_at', s.first_response_at,
            'responses_count', (
                select count(*)
                from event_survey_response r
                where r.event_survey_id = s.event_survey_id
            )
        )
        from event_survey s
        where s.event_survey_id = :'lockedSurveyID'
    ),
    jsonb_build_object(
        'first_response_at', current_timestamp - interval '1 day',
        'responses_count', 2
    ),
    'Should store the later response without changing the first response time'
);

-- Should reject answers from users outside the survey audience
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'checkedInSurveyID', :'respondentID', :'answers'
    ),
    'OCG01',
    'you are not eligible to answer this survey',
    'Should reject answers from users outside the survey audience'
);

-- Should reject answers given to a stale survey revision
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'staleSurveyID', :'respondentID', :'answers'
    ),
    'OCG01',
    'the survey changed; review and try again',
    'Should reject answers given to a stale survey revision'
);

-- Should reject answers to closed surveys
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'closedSurveyID', :'respondentID', :'answers'
    ),
    'OCG01',
    'event survey is not open',
    'Should reject answers to closed surveys'
);

-- Should reject answers to surveys of canceled events
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'canceledEventSurveyID', :'respondentID', :'answers'
    ),
    'OCG01',
    'event survey not found',
    'Should reject answers to surveys of canceled events'
);

-- Should reject answers to unknown surveys
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'respondentID', :'respondentID', :'answers'
    ),
    'OCG01',
    'event survey not found',
    'Should reject answers to unknown surveys'
);

-- Should reject invalid answers
select throws_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'invalidAnswersSurveyID', :'respondentID', '{"answers": []}'
    ),
    'OCG01',
    'required questionnaire answer is missing',
    'Should reject invalid answers'
);

-- Should store a first response and record the first response time
select lives_ok(
    format(
        $$select submit_event_survey_response(%L::uuid, %L::uuid, 1, %L::jsonb)$$,
        :'newResponseSurveyID', :'respondentID', :'answers'
    ),
    'Should store a first response and record the first response time'
);
select is(
    (
        select jsonb_build_object(
            'answers', r.answers,
            'created_at', r.created_at,
            'updated_at', r.updated_at
        )
        from event_survey_response r
        where r.event_survey_id = :'newResponseSurveyID'
        and r.user_id = :'respondentID'
    ),
    jsonb_build_object(
        'answers', :'answers'::jsonb,
        'created_at', current_timestamp,
        'updated_at', null
    ),
    'Should store the first response answers'
);
select is(
    (
        select s.first_response_at
        from event_survey s
        where s.event_survey_id = :'newResponseSurveyID'
    ),
    current_timestamp,
    'Should record the first response time'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
