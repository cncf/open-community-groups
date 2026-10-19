-- Tests checking whether a survey is reachable on the public site.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID 'a5e00030-0000-0000-0000-000000000001'
\set canceledEventSurveyID 'a5e00030-0000-0000-0000-000000000002'
\set communityID 'a5e00030-0000-0000-0000-000000000003'
\set draftSurveyID 'a5e00030-0000-0000-0000-000000000004'
\set eventCategoryID 'a5e00030-0000-0000-0000-000000000005'
\set eventID 'a5e00030-0000-0000-0000-000000000006'
\set groupCategoryID 'a5e00030-0000-0000-0000-000000000007'
\set groupID 'a5e00030-0000-0000-0000-000000000008'
\set inactiveCommunityEventCategoryID 'a5e00030-0000-0000-0000-000000000009'
\set inactiveCommunityEventID 'a5e00030-0000-0000-0000-00000000000a'
\set inactiveCommunityGroupCategoryID 'a5e00030-0000-0000-0000-00000000000b'
\set inactiveCommunityGroupID 'a5e00030-0000-0000-0000-00000000000c'
\set inactiveCommunityID 'a5e00030-0000-0000-0000-00000000000d'
\set inactiveCommunitySurveyID 'a5e00030-0000-0000-0000-00000000000e'
\set otherCommunityID 'a5e00030-0000-0000-0000-000000000012'
\set otherEventID 'a5e00030-0000-0000-0000-000000000013'
\set otherGroupID 'a5e00030-0000-0000-0000-000000000014'
\set readySurveyID 'a5e00030-0000-0000-0000-00000000000f'
\set unpublishedEventID 'a5e00030-0000-0000-0000-000000000010'
\set unpublishedEventSurveyID 'a5e00030-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Active community hosting the public surveys
select fx_community(:'communityID', jsonb_build_object('active', true));

-- Inactive community hosting a hidden survey
select fx_community(:'inactiveCommunityID', jsonb_build_object('active', false));

-- Active community the public event group does not belong to
select fx_community(:'otherCommunityID', jsonb_build_object('active', true));

-- Event category of the active community
select fx_event_category(:'eventCategoryID', :'communityID');

-- Event category of the inactive community
select fx_event_category(:'inactiveCommunityEventCategoryID', :'inactiveCommunityID');

-- Group category of the active community
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group category of the inactive community
select fx_group_category(:'inactiveCommunityGroupCategoryID', :'inactiveCommunityID');

-- Active group of the active community
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Other active group of the active community
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Active group of the inactive community
select fx_group(
    :'inactiveCommunityGroupID',
    :'inactiveCommunityID',
    :'inactiveCommunityGroupCategoryID',
    jsonb_build_object('active', true)
);

-- Canceled published event
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true
));

-- Published event of the active community
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Published event of the inactive community
select fx_event(
    :'inactiveCommunityEventID',
    :'inactiveCommunityGroupID',
    :'inactiveCommunityEventCategoryID',
    jsonb_build_object('published', true)
);

-- Other published event of the active community
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Unpublished event of the active community
select fx_event(:'unpublishedEventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', false));

-- Ready survey of the canceled event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'canceledEventSurveyID', :'canceledEventID', 'ready', 'Canceled event survey');

-- Draft survey of the public event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'draftSurveyID', :'eventID', 'draft', 'Draft survey');

-- Ready survey of the inactive community event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'inactiveCommunitySurveyID', :'inactiveCommunityEventID', 'ready', 'Inactive community survey');

-- Ready survey of the public event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'readySurveyID', :'eventID', 'ready', 'Ready survey');

-- Ready survey of the unpublished event
insert into event_survey (event_survey_id, event_id, status, title)
values (:'unpublishedEventSurveyID', :'unpublishedEventID', 'ready', 'Unpublished event survey');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should hide draft surveys
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.event_survey_id = :'draftSurveyID'
    ),
    false,
    'Should hide draft surveys'
);

-- Should hide surveys of canceled events
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.event_survey_id = :'canceledEventSurveyID'
    ),
    false,
    'Should hide surveys of canceled events'
);

-- Should hide surveys of events whose page is not public
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.event_survey_id = :'unpublishedEventSurveyID'
    ),
    false,
    'Should hide surveys of events whose page is not public'
);

-- Should hide surveys of inactive communities
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.event_survey_id = :'inactiveCommunitySurveyID'
    ),
    false,
    'Should hide surveys of inactive communities'
);

-- Should hide surveys passed with another event
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s, event e, "group" g, community c
        where s.event_survey_id = :'readySurveyID'
        and e.event_id = :'otherEventID'
        and g.group_id = :'groupID'
        and c.community_id = :'communityID'
    ),
    false,
    'Should hide surveys passed with another event'
);

-- Should hide surveys whose event belongs to another group
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s, event e, "group" g, community c
        where s.event_survey_id = :'readySurveyID'
        and e.event_id = :'eventID'
        and g.group_id = :'otherGroupID'
        and c.community_id = :'communityID'
    ),
    false,
    'Should hide surveys whose event belongs to another group'
);

-- Should hide surveys whose group belongs to another community
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s, event e, "group" g, community c
        where s.event_survey_id = :'readySurveyID'
        and e.event_id = :'eventID'
        and g.group_id = :'groupID'
        and c.community_id = :'otherCommunityID'
    ),
    false,
    'Should hide surveys whose group belongs to another community'
);

-- Should show ready surveys of public events in active communities
select is(
    (
        select is_event_survey_public(s, e, g, c)
        from event_survey s
        join event e on e.event_id = s.event_id
        join "group" g on g.group_id = e.group_id
        join community c on c.community_id = g.community_id
        where s.event_survey_id = :'readySurveyID'
    ),
    true,
    'Should show ready surveys of public events in active communities'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
