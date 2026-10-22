-- Tests listing the surveys a user reaches from the dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledClosedSurveyID 'a5e00037-0000-0000-0000-000000000001'
\set canceledEventID 'a5e00037-0000-0000-0000-000000000002'
\set canceledOpenSurveyID 'a5e00037-0000-0000-0000-000000000003'
\set checkedInSurveyID 'a5e00037-0000-0000-0000-000000000004'
\set closedByDateSurveyID 'a5e00037-0000-0000-0000-000000000005'
\set closedManuallySurveyID 'a5e00037-0000-0000-0000-000000000006'
\set closedUnansweredSurveyID 'a5e00037-0000-0000-0000-000000000007'
\set communityID 'a5e00037-0000-0000-0000-000000000008'
\set draftSurveyID 'a5e00037-0000-0000-0000-000000000009'
\set eventCategoryID 'a5e00037-0000-0000-0000-00000000000a'
\set eventID 'a5e00037-0000-0000-0000-00000000000b'
\set formerClosedSurveyID 'a5e00037-0000-0000-0000-00000000000c'
\set formerEventID 'a5e00037-0000-0000-0000-00000000000d'
\set formerOpenSurveyID 'a5e00037-0000-0000-0000-00000000000e'
\set groupCategoryID 'a5e00037-0000-0000-0000-00000000000f'
\set groupID 'a5e00037-0000-0000-0000-000000000010'
\set openAnsweredSurveyID 'a5e00037-0000-0000-0000-000000000011'
\set openUnansweredSurveyID 'a5e00037-0000-0000-0000-000000000012'
\set outsiderID 'a5e00037-0000-0000-0000-000000000013'
\set respondentID 'a5e00037-0000-0000-0000-000000000014'
\set scheduledSurveyID 'a5e00037-0000-0000-0000-000000000015'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the surveyed events
select fx_community(:'communityID', jsonb_build_object('active', true));

-- User outside every survey audience
select fx_user(:'outsiderID');

-- Confirmed attendee, without check-in, of the main and canceled events
select fx_user(:'respondentID');

-- Event category of the community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category of the community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Active group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Canceled published event that already ended
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', current_timestamp - interval '3 days',
    'published', true,
    'starts_at', current_timestamp - interval '3 days 2 hours'
));

-- Published ended event hosting most surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '3 days',
    'published', true,
    'starts_at', current_timestamp - interval '3 days 2 hours'
));

-- Published ended event the respondent no longer attends
select fx_event(:'formerEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '3 days',
    'published', true,
    'starts_at', current_timestamp - interval '3 days 2 hours'
));

-- Confirmed attendance of the respondent at the canceled event
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'canceledEventID', 'confirmed', :'respondentID');

-- Confirmed attendance of the respondent at the main event
insert into event_attendee (checked_in, event_id, status, user_id)
values (false, :'eventID', 'confirmed', :'respondentID');

-- Survey of the canceled event closed after the respondent answered it
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'canceledClosedSurveyID', :'canceledEventID', 'ready', 'Canceled closed', current_timestamp - interval '1 hour');

-- Open survey of the canceled event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'canceledOpenSurveyID', :'canceledEventID', 'ready', 'Canceled open');

-- Open survey limited to checked-in attendees
insert into event_survey (event_survey_id, audience, event_id, status, title)
values (:'checkedInSurveyID', 'checked-in', :'eventID', 'ready', 'Checked-in only');

-- Survey past its closing date, closed manually later
insert into event_survey (event_survey_id, event_id, status, title, closed_at, closes_at)
values (
    :'closedByDateSurveyID',
    :'eventID',
    'ready',
    'Closed by date',
    current_timestamp - interval '1 hour',
    current_timestamp - interval '1 day'
);

-- Survey closed manually before its closing date
insert into event_survey (event_survey_id, event_id, status, title, closed_at, closes_at)
values (
    :'closedManuallySurveyID',
    :'eventID',
    'ready',
    'Closed manually',
    current_timestamp - interval '2 hours',
    current_timestamp + interval '5 days'
);

-- Survey closed without a response from the respondent
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'closedUnansweredSurveyID', :'eventID', 'ready', 'Closed unanswered', current_timestamp - interval '1 hour');

-- Draft survey of the main event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'eventID', 'draft', 'Draft');

-- Survey of the former event closed after the respondent answered it
insert into event_survey (event_survey_id, event_id, status, title, closed_at)
values (:'formerClosedSurveyID', :'formerEventID', 'ready', 'Former closed', current_timestamp - interval '1 hour');

-- Open survey of the former event the respondent answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'formerOpenSurveyID', :'formerEventID', 'ready', 'Former open');

-- Open survey the respondent answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'openAnsweredSurveyID', :'eventID', 'ready', 'Open answered');

-- Open survey the respondent has not answered
insert into event_survey (event_survey_id, event_id, status, title)
values (:'openUnansweredSurveyID', :'eventID', 'ready', 'Open unanswered');

-- Ready survey whose custom opening is in the future
insert into event_survey (event_survey_id, event_id, status, title, opens_at)
values (:'scheduledSurveyID', :'eventID', 'ready', 'Scheduled', current_timestamp + interval '1 day');

-- Responses of the respondent to the answered surveys
insert into event_survey_response (answers, event_survey_id, user_id)
select '{"answers": []}'::jsonb, event_survey_id, :'respondentID'
from unnest(array[
    :'canceledClosedSurveyID',
    :'closedByDateSurveyID',
    :'closedManuallySurveyID',
    :'formerClosedSurveyID',
    :'formerOpenSurveyID',
    :'openAnsweredSurveyID'
]::uuid[]) as event_survey_id;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should close surveys at their closing date when it comes first
select is(
    (
        select us.closed_at
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id = :'closedByDateSurveyID'::uuid
    ),
    current_timestamp - interval '1 day',
    'Should close surveys at their closing date when it comes first'
);

-- Should close surveys at their manual close when it comes first
select is(
    (
        select us.closed_at
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id = :'closedManuallySurveyID'::uuid
    ),
    current_timestamp - interval '2 hours',
    'Should close surveys at their manual close when it comes first'
);

-- Should exclude closed surveys the user did not answer
select ok(
    not exists (
        select 1
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id = :'closedUnansweredSurveyID'::uuid
    ),
    'Should exclude closed surveys the user did not answer'
);

-- Should exclude draft and scheduled surveys
select ok(
    not exists (
        select 1
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id in (:'draftSurveyID'::uuid, :'scheduledSurveyID'::uuid)
    ),
    'Should exclude draft and scheduled surveys'
);

-- Should exclude open surveys outside the user audience
select ok(
    not exists (
        select 1
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id = :'checkedInSurveyID'::uuid
    ),
    'Should exclude open surveys outside the user audience'
);

-- Should exclude open surveys the user answered before leaving the audience
select ok(
    not exists (
        select 1
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id = :'formerOpenSurveyID'::uuid
    ),
    'Should exclude open surveys the user answered before leaving the audience'
);

-- Should exclude surveys attendees cannot reach on the public site
select ok(
    not exists (
        select 1
        from user_dashboard_event_surveys(:'respondentID'::uuid) us
        where us.event_survey_id in (:'canceledClosedSurveyID'::uuid, :'canceledOpenSurveyID'::uuid)
    ),
    'Should exclude surveys attendees cannot reach on the public site'
);

-- Should keep closed surveys the user answered before leaving the audience
select results_eq(
    format(
        $$
            select us.answered, us.state
            from user_dashboard_event_surveys(%L::uuid) us
            where us.event_survey_id = %L::uuid
        $$,
        :'respondentID',
        :'formerClosedSurveyID'
    ),
    $$ values (true, 'closed'::text) $$,
    'Should keep closed surveys the user answered before leaving the audience'
);

-- Should list open surveys with whether the user answered them
select results_eq(
    format(
        $$
            select us.answered, us.closed_at, us.event_survey_id, us.state
            from user_dashboard_event_surveys(%L::uuid) us
            where us.state = 'open'
            order by us.event_survey_id
        $$,
        :'respondentID'
    ),
    format(
        $$
            values
                (true, null::timestamptz, %L::uuid, 'open'::text),
                (false, null::timestamptz, %L::uuid, 'open'::text)
        $$,
        :'openAnsweredSurveyID',
        :'openUnansweredSurveyID'
    ),
    'Should list open surveys with whether the user answered them'
);

-- Should list the closed surveys the user answered
select results_eq(
    format(
        $$
            select us.event_survey_id
            from user_dashboard_event_surveys(%L::uuid) us
            where us.state = 'closed'
            order by us.event_survey_id
        $$,
        :'respondentID'
    ),
    format(
        $$ values (%L::uuid), (%L::uuid), (%L::uuid) $$,
        :'closedByDateSurveyID',
        :'closedManuallySurveyID',
        :'formerClosedSurveyID'
    ),
    'Should list the closed surveys the user answered'
);

-- Should return nothing for users outside every audience
select is_empty(
    format(
        $$ select * from user_dashboard_event_surveys(%L::uuid) $$,
        :'outsiderID'
    ),
    'Should return nothing for users outside every audience'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
