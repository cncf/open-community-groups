-- Tests listing the surveys of a group event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'a5e00011-0000-0000-0000-000000000001'
\set emptyEventID 'a5e00011-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00011-0000-0000-0000-000000000005'
\set eventID 'a5e00011-0000-0000-0000-000000000006'
\set firstSurveyID 'a5e00011-0000-0000-0000-000000000007'
\set foreignGroupID 'a5e00011-0000-0000-0000-000000000008'
\set groupCategoryID 'a5e00011-0000-0000-0000-000000000009'
\set groupID 'a5e00011-0000-0000-0000-00000000000a'
\set laterSurveyID 'a5e00011-0000-0000-0000-00000000000b'
\set secondSurveyID 'a5e00011-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that does not own the surveyed event
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event without surveys
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID');

-- Event with several surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Survey created first, sharing its creation time with the second one
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'firstSurveyID', '2025-01-01 10:00:00+00', :'eventID', 'First survey');

-- Survey created after the others
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'laterSurveyID', '2025-01-02 10:00:00+00', :'eventID', 'Later survey');

-- Survey sharing its creation time with the first one
insert into event_survey (event_survey_id, created_at, event_id, title)
values (:'secondSurveyID', '2025-01-01 10:00:00+00', :'eventID', 'Second survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list surveys by creation time and identifier
select is(
    jsonb_path_query_array(
        list_event_surveys(:'groupID'::uuid, :'eventID'::uuid)::jsonb,
        '$[*].event_survey_id'
    ),
    jsonb_build_array(:'firstSurveyID'::uuid, :'secondSurveyID'::uuid, :'laterSurveyID'::uuid),
    'Should list surveys by creation time and identifier'
);

-- Should project each survey with the shared summary
select is(
    list_event_surveys(:'groupID'::uuid, :'eventID'::uuid)::jsonb->0,
    (
        select event_survey_summary_json(s, e)
        from event_survey s
        join event e on e.event_id = s.event_id
        where s.event_survey_id = :'firstSurveyID'
    ),
    'Should project each survey with the shared summary'
);

-- Should return an empty list for events of another group
select is(
    list_event_surveys(:'foreignGroupID'::uuid, :'eventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty list for events of another group'
);

-- Should return an empty list for events without surveys
select is(
    list_event_surveys(:'groupID'::uuid, :'emptyEventID'::uuid)::jsonb,
    '[]'::jsonb,
    'Should return an empty list for events without surveys'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
