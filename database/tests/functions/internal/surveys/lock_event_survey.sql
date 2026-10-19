-- Tests locking a survey of an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00004-0000-0000-0000-000000000001'
\set eventCategoryID 'a5e00004-0000-0000-0000-000000000002'
\set eventID 'a5e00004-0000-0000-0000-000000000003'
\set groupCategoryID 'a5e00004-0000-0000-0000-000000000004'
\set groupID 'a5e00004-0000-0000-0000-000000000005'
\set missingSurveyID 'a5e00004-0000-0000-0000-000000000006'
\set otherEventID 'a5e00004-0000-0000-0000-000000000007'
\set otherSurveyID 'a5e00004-0000-0000-0000-000000000008'
\set surveyID 'a5e00004-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the surveyed events group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event owning the locked survey
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Other event owning a survey requested through the wrong event
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Survey of the other event
insert into event_survey (event_survey_id, event_id, title)
values (:'otherSurveyID', :'otherEventID', 'Other survey');

-- Survey locked by the successful scenario
insert into event_survey (event_survey_id, event_id, title)
values (:'surveyID', :'eventID', 'Survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the survey row
select is(
    (select (lock_event_survey(:'eventID', :'surveyID')).title),
    'Survey',
    'Should return the survey row'
);

-- Should reject missing surveys
select throws_ok(
    format($$select lock_event_survey(%L::uuid, %L::uuid)$$, :'eventID', :'missingSurveyID'),
    'OCG01',
    'event survey not found',
    'Should reject missing surveys'
);

-- Should reject surveys of another event
select throws_ok(
    format($$select lock_event_survey(%L::uuid, %L::uuid)$$, :'eventID', :'otherSurveyID'),
    'OCG01',
    'event survey not found',
    'Should reject surveys of another event'
);

-- Should lock the survey row for update
-- Relies on the lock taken by the survey row scenario above
select is(
    (select xmax::text from event_survey where event_survey_id = :'surveyID'),
    (pg_current_xact_id()::text::bigint % 4294967296)::text,
    'Should lock the survey row for update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
