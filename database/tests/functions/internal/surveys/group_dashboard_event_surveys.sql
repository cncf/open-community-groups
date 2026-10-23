-- Tests resolving the surveys of a group event read by the organizer dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00042-0000-0000-0000-000000000001'
\set canceledSurveyID 'a5e00042-0000-0000-0000-000000000002'
\set communityID 'a5e00042-0000-0000-0000-000000000003'
\set deletedEventID 'a5e00042-0000-0000-0000-000000000004'
\set deletedSurveyID 'a5e00042-0000-0000-0000-000000000005'
\set eventCategoryID 'a5e00042-0000-0000-0000-000000000006'
\set eventID 'a5e00042-0000-0000-0000-000000000007'
\set firstSurveyID 'a5e00042-0000-0000-0000-000000000008'
\set foreignGroupID 'a5e00042-0000-0000-0000-000000000009'
\set groupCategoryID 'a5e00042-0000-0000-0000-00000000000a'
\set groupID 'a5e00042-0000-0000-0000-00000000000b'
\set inactiveGroupEventID 'a5e00042-0000-0000-0000-00000000000c'
\set inactiveGroupID 'a5e00042-0000-0000-0000-00000000000d'
\set inactiveGroupSurveyID 'a5e00042-0000-0000-0000-00000000000e'
\set otherEventID 'a5e00042-0000-0000-0000-00000000000f'
\set otherEventSurveyID 'a5e00042-0000-0000-0000-000000000010'
\set secondSurveyID 'a5e00042-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the surveyed events
select fx_community(:'communityID');

-- Event category used by the surveyed events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the groups
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group that does not own the surveyed events
select fx_group(:'foreignGroupID', :'communityID', :'groupCategoryID');

-- Group hosting the surveyed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Inactive group whose event surveys organizers still read
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Canceled event whose survey organizers still read
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object('canceled', true));

-- Deleted event whose survey is hidden
select fx_event(:'deletedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'deleted_at', '2025-01-01 10:00:00+00'
));

-- Event with several surveys
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Event of the inactive group
select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID');

-- Event of the same group that does not own the surveys of the main event
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');

-- Survey of the canceled event
insert into event_survey (event_survey_id, event_id, title)
values (:'canceledSurveyID', :'canceledEventID', 'Canceled event survey');

-- Survey of the deleted event
insert into event_survey (event_survey_id, event_id, title)
values (:'deletedSurveyID', :'deletedEventID', 'Deleted event survey');

-- First survey of the main event
insert into event_survey (event_survey_id, event_id, title)
values (:'firstSurveyID', :'eventID', 'First survey');

-- Survey of the event of the inactive group
insert into event_survey (event_survey_id, event_id, title)
values (:'inactiveGroupSurveyID', :'inactiveGroupEventID', 'Inactive group survey');

-- Survey of the other event of the group
insert into event_survey (event_survey_id, event_id, title)
values (:'otherEventSurveyID', :'otherEventID', 'Other event survey');

-- Second survey of the main event
insert into event_survey (event_survey_id, event_id, title)
values (:'secondSurveyID', :'eventID', 'Second survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep surveys of canceled events
select results_eq(
    format(
        $$
            select (gs.event_survey_row).event_survey_id
            from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) gs
        $$,
        :'groupID',
        :'canceledEventID',
        :'canceledSurveyID'
    ),
    format($$ values (%L::uuid) $$, :'canceledSurveyID'),
    'Should keep surveys of canceled events'
);

-- Should keep surveys of events of inactive groups
select results_eq(
    format(
        $$
            select (gs.event_survey_row).event_survey_id
            from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) gs
        $$,
        :'inactiveGroupID',
        :'inactiveGroupEventID',
        :'inactiveGroupSurveyID'
    ),
    format($$ values (%L::uuid) $$, :'inactiveGroupSurveyID'),
    'Should keep surveys of events of inactive groups'
);

-- Should return every survey of the event when no survey is given
select results_eq(
    format(
        $$
            select (gs.event_survey_row).event_survey_id
            from group_dashboard_event_surveys(%L::uuid, %L::uuid) gs
            order by 1
        $$,
        :'groupID',
        :'eventID'
    ),
    format($$ values (%L::uuid), (%L::uuid) $$, :'firstSurveyID', :'secondSurveyID'),
    'Should return every survey of the event when no survey is given'
);

-- Should return no rows for deleted events
select is_empty(
    format(
        $$ select * from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) $$,
        :'groupID',
        :'deletedEventID',
        :'deletedSurveyID'
    ),
    'Should return no rows for deleted events'
);

-- Should return no rows for events of another group
select is_empty(
    format(
        $$ select * from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) $$,
        :'foreignGroupID',
        :'eventID',
        :'firstSurveyID'
    ),
    'Should return no rows for events of another group'
);

-- Should return no rows for surveys of another event
select is_empty(
    format(
        $$ select * from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) $$,
        :'groupID',
        :'eventID',
        :'otherEventSurveyID'
    ),
    'Should return no rows for surveys of another event'
);

-- Should return the requested survey of the group event with its event row
select results_eq(
    format(
        $$
            select gs.event_row::text, gs.event_survey_row::text
            from group_dashboard_event_surveys(%L::uuid, %L::uuid, %L::uuid) gs
        $$,
        :'groupID',
        :'eventID',
        :'firstSurveyID'
    ),
    format(
        $$
            select e::text, s::text
            from event e
            join event_survey s on s.event_id = e.event_id
            where s.event_survey_id = %L::uuid
        $$,
        :'firstSurveyID'
    ),
    'Should return the requested survey of the group event with its event row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
