-- Tests summarizing the surveys of an event for analytics.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set checkedInUserID 'a5e00010-0000-0000-0000-000000000001'
\set closedSurveyID 'a5e00010-0000-0000-0000-000000000002'
\set communityID 'a5e00010-0000-0000-0000-000000000003'
\set confirmedUserID 'a5e00010-0000-0000-0000-000000000004'
\set draftOnlyEventID 'a5e00010-0000-0000-0000-000000000005'
\set draftOnlySurveyID 'a5e00010-0000-0000-0000-000000000006'
\set draftSurveyID 'a5e00010-0000-0000-0000-000000000007'
\set eventCategoryID 'a5e00010-0000-0000-0000-000000000008'
\set eventID 'a5e00010-0000-0000-0000-000000000009'
\set groupCategoryID 'a5e00010-0000-0000-0000-00000000000a'
\set groupID 'a5e00010-0000-0000-0000-00000000000b'
\set openSurveyID 'a5e00010-0000-0000-0000-00000000000c'
\set scheduledSurveyID 'a5e00010-0000-0000-0000-00000000000d'
\set silentUserID 'a5e00010-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Confirmed attendee who checked in and answered
select fx_user(:'checkedInUserID');

-- Confirmed attendee who answered without checking in
select fx_user(:'confirmedUserID');

-- Confirmed attendee who did not answer
select fx_user(:'silentUserID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Published ended event whose surveys only include a draft
select fx_event(:'draftOnlyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Published ended event with surveys in every state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', '2025-01-01 12:00:00+00',
    'published', true,
    'starts_at', '2025-01-01 10:00:00+00'
));

-- Confirmed attendee who checked in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'checkedInUserID', true, 'confirmed');

-- Confirmed attendee who did not check in
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'confirmedUserID', false, 'confirmed');

-- Confirmed attendee who did not answer
insert into event_attendee (event_id, user_id, checked_in, status)
values (:'eventID', :'silentUserID', false, 'confirmed');

-- Ready survey for checked-in attendees closed manually
insert into event_survey (
    event_survey_id,
    audience,
    created_at,
    event_id,
    status,
    title,

    closed_at
) values (
    :'closedSurveyID',
    'checked-in',
    '2025-01-03 10:00:00+00',
    :'eventID',
    'ready',
    'Closed survey',

    '2025-01-05 10:00:00+00'
);

-- Draft survey of the event that only has a draft
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'draftOnlySurveyID', '2025-01-02 10:00:00+00', :'draftOnlyEventID', 'Draft only survey');

-- Draft survey left out of the summary
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'draftSurveyID', '2025-01-01 10:00:00+00', :'eventID', 'Draft survey');

-- Ready survey open to confirmed attendees
insert into event_survey (event_survey_id, created_at, event_id, status, title)
values (:'openSurveyID', '2025-01-02 10:00:00+00', :'eventID', 'ready', 'Open survey');

-- Ready survey scheduled to open in the future
insert into event_survey (
    event_survey_id,
    created_at,
    event_id,
    status,
    title,

    opens_at
) values (
    :'scheduledSurveyID',
    '2025-01-04 10:00:00+00',
    :'eventID',
    'ready',
    'Scheduled survey',

    '2099-01-01 00:00:00+00'
);

-- Closed survey response from the checked-in attendee
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'closedSurveyID', :'checkedInUserID');

-- Closed survey response from the attendee who did not check in
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'closedSurveyID', :'confirmedUserID');

-- Open survey response from the checked-in attendee
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'openSurveyID', :'checkedInUserID');

-- Open survey response from the attendee who did not check in
insert into event_survey_response (answers, event_survey_id, user_id)
values ('{"answers": []}', :'openSurveyID', :'confirmedUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report no surveys for events with drafts only
select is(
    (
        select stats_event_surveys(e)::jsonb
        from event e
        where e.event_id = :'draftOnlyEventID'
    ),
    jsonb_build_object(
        'surveys', '[]'::jsonb,
        'total_eligible_count', 0,
        'total_eligible_respondents_count', 0
    ),
    'Should report no surveys for events with drafts only'
);

-- Should summarize ready surveys and total the opened ones
select is(
    (
        select stats_event_surveys(e)::jsonb
        from event e
        where e.event_id = :'eventID'
    ),
    jsonb_build_object(
        'surveys', jsonb_build_array(
            jsonb_build_object(
                'eligible_count', 3,
                'eligible_respondents_count', 2,
                'event_survey_id', :'openSurveyID'::uuid,
                'responses_count', 2,
                'state', 'open',
                'title', 'Open survey'
            ),
            jsonb_build_object(
                'eligible_count', 1,
                'eligible_respondents_count', 1,
                'event_survey_id', :'closedSurveyID'::uuid,
                'responses_count', 2,
                'state', 'closed',
                'title', 'Closed survey'
            ),
            jsonb_build_object(
                'eligible_count', 3,
                'eligible_respondents_count', 0,
                'event_survey_id', :'scheduledSurveyID'::uuid,
                'responses_count', 0,
                'state', 'scheduled',
                'title', 'Scheduled survey'
            )
        ),
        'total_eligible_count', 4,
        'total_eligible_respondents_count', 3
    ),
    'Should summarize ready surveys and total the opened ones'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
