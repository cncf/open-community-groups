-- Tests projecting the survey summary shared by the dashboard readers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledUserID 'a5e0000a-0000-0000-0000-000000000001'
\set checkedInUserID 'a5e0000a-0000-0000-0000-000000000002'
\set closedSurveyID 'a5e0000a-0000-0000-0000-000000000003'
\set communityID 'a5e0000a-0000-0000-0000-000000000004'
\set confirmedUserID 'a5e0000a-0000-0000-0000-000000000005'
\set draftSurveyID 'a5e0000a-0000-0000-0000-000000000006'
\set eventCategoryID 'a5e0000a-0000-0000-0000-000000000007'
\set eventID 'a5e0000a-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e0000a-0000-0000-0000-000000000009'
\set groupID 'a5e0000a-0000-0000-0000-00000000000a'
\set identifiedSurveyID 'a5e0000a-0000-0000-0000-00000000000b'
\set openAnonymousSurveyID 'a5e0000a-0000-0000-0000-00000000000f'
\set processedAnonymousSurveyID 'a5e0000a-0000-0000-0000-000000000010'
\set scheduledAnonymousSurveyID 'a5e0000a-0000-0000-0000-000000000011'
\set silentUserID 'a5e0000a-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed event
select fx_community(:'communityID');

-- User whose attendance was canceled after answering
select fx_user(:'canceledUserID');

-- Confirmed attendee who checked in and answered
select fx_user(:'checkedInUserID');

-- Confirmed attendee who answered without checking in
select fx_user(:'confirmedUserID');

-- Confirmed attendee who did not answer
select fx_user(:'silentUserID');

-- Event category used by the surveyed event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed event group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published event that already ended
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Canceled attendance that answered the identified survey
insert into event_attendee (event_id, user_id, checked_in, status, attendance_canceled_at)
values (:'eventID', :'canceledUserID', true, 'attendance-canceled', '2025-01-01 11:00:00+00');

-- Confirmed attendee who checked in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'checkedInUserID', true, 'confirmed');

-- Confirmed attendee who did not check in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'confirmedUserID', false, 'confirmed');

-- Confirmed attendee who did not answer
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'silentUserID', false, 'confirmed');

-- Ready survey closed manually
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedSurveyID', :'eventID', 'ready', 'Closed survey', '2025-01-03 10:00:00+00');

-- Draft survey with default settings
insert into event_survey (event_survey_id, event_id, title)
values (:'draftSurveyID', :'eventID', 'Draft survey');

-- Ready identified survey for checked-in attendees with responses
insert into event_survey (
    event_survey_id,
    anonymous,
    audience,
    event_id,
    questions,
    revision,
    status,
    title,

    closes_at,
    first_response_at,
    open_notification_processed_at,
    open_notification_recipients
) values (
    :'identifiedSurveyID',
    false,
    'checked-in',
    :'eventID',
    '[
        {"id": "a5e0000a-0000-0000-0000-00000000000d", "kind": "free-text", "prompt": "Feedback", "required": false},
        {"id": "a5e0000a-0000-0000-0000-00000000000e", "kind": "free-text", "prompt": "Ideas", "required": false}
    ]',
    3,
    'ready',
    'Identified survey',

    '2099-01-01 00:00:00+00',
    '2025-01-02 11:00:00+00',
    '2025-01-02 10:00:00+00',
    1
);

-- Open anonymous survey whose opening email was not processed yet
insert into event_survey (event_survey_id, event_id, status, title)
values (:'openAnonymousSurveyID', :'eventID', 'ready', 'Open anonymous survey');

-- Scheduled anonymous survey whose opening email was already processed
insert into event_survey (
    event_survey_id,
    event_id,
    status,
    title,

    open_notification_processed_at,
    open_notification_recipients,
    opens_at
) values (
    :'processedAnonymousSurveyID',
    :'eventID',
    'ready',
    'Processed anonymous survey',

    '2025-01-02 10:00:00+00',
    0,
    '2099-01-01 00:00:00+00'
);

-- Scheduled anonymous survey whose opening email was not processed yet
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'scheduledAnonymousSurveyID', :'eventID', 'ready', 'Scheduled anonymous survey', '2099-01-01 00:00:00+00');

-- Response from the canceled attendance
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}', :'identifiedSurveyID', :'canceledUserID');

-- Response from the checked-in attendee
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}', :'identifiedSurveyID', :'checkedInUserID');

-- Response from the attendee who did not check in
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{}', :'identifiedSurveyID', :'confirmedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should flag manually closed surveys
select is(
    (
        select jsonb_build_array(
            event_survey_summary_json(s, e)->'closed_manually',
            event_survey_summary_json(s, e)->'state'
        )
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'closedSurveyID'
    ),
    '[true, "closed"]'::jsonb,
    'Should flag manually closed surveys'
);

-- Should lock the anonymity of anonymous surveys once they open or their email is processed
select is(
    (
        select jsonb_object_agg(s.title, event_survey_summary_json(s, e)->'anonymous_locked')
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_id = :'eventID'
    ),
    jsonb_build_object(
        'Closed survey', true,
        'Draft survey', false,
        'Identified survey', false,
        'Open anonymous survey', true,
        'Processed anonymous survey', true,
        'Scheduled anonymous survey', false
    ),
    'Should lock the anonymity of anonymous surveys once they open or their email is processed'
);

-- Should project draft surveys with default settings
select is(
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'draftSurveyID'
    ),
    jsonb_build_object(
        'anonymous', true,
        'audience', 'confirmed',
        'event_survey_id', :'draftSurveyID'::uuid,
        'revision', 1,
        'title', 'Draft survey',

        'closes_at', null,
        'open_notification_processed_at', null,

        'anonymous_locked', false,
        'closed_manually', false,
        'effective_opens_at', 1735732800,
        'eligible_count', 3,
        'eligible_respondents_count', 0,
        'locked', false,
        'questions_count', 0,
        'responses_count', 0,
        'state', 'draft'
    ),
    'Should project draft surveys with default settings'
);

-- Should project responded surveys with live counts
select is(
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'identifiedSurveyID'
    ),
    jsonb_build_object(
        'anonymous', false,
        'audience', 'checked-in',
        'event_survey_id', :'identifiedSurveyID'::uuid,
        'revision', 3,
        'title', 'Identified survey',

        'closes_at', 4070908800,
        'open_notification_processed_at', 1735812000,

        'anonymous_locked', false,
        'closed_manually', false,
        'effective_opens_at', 1735732800,
        'eligible_count', 1,
        'eligible_respondents_count', 1,
        'locked', true,
        'questions_count', 2,
        'responses_count', 3,
        'state', 'open'
    ),
    'Should project responded surveys with live counts'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
