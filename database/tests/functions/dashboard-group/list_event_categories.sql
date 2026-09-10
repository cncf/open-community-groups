-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '3a190000-0000-0000-0000-000000000001'
\set community2ID '3a190000-0000-0000-0000-000000000002'
\set eventCategoryConferenceID '3a190000-0000-0000-0000-000000000003'
\set eventCategoryMeetupID '3a190000-0000-0000-0000-000000000004'
\set eventCategorySeminarID '3a190000-0000-0000-0000-000000000005'
\set eventCategoryWorkshopID '3a190000-0000-0000-0000-000000000006'
\set eventConferenceDay1ID '3a190000-0000-0000-0000-000000000007'
\set eventConferenceDay2ID '3a190000-0000-0000-0000-000000000008'
\set eventSeminarKeynoteID '3a190000-0000-0000-0000-000000000009'
\set eventWorkshopLabID '3a190000-0000-0000-0000-000000000010'
\set groupCategoryBusinessID '3a190000-0000-0000-0000-000000000011'
\set groupCategoryTechnologyID '3a190000-0000-0000-0000-000000000012'
\set groupDevopsID '3a190000-0000-0000-0000-000000000013'
\set groupKubernetesID '3a190000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities
select fx_community(:'community1ID');

-- Community
select fx_community(:'community2ID', jsonb_build_object(
    'display_name', 'DevOps Vancouver',
    'name', 'devops-vancouver'
));

-- Group categories
select fx_group_category(:'groupCategoryTechnologyID', :'community1ID', jsonb_build_object('name', 'Technology'));
select fx_group_category(:'groupCategoryBusinessID', :'community2ID', jsonb_build_object('name', 'Business'));

-- Event categories
select fx_event_category(:'eventCategoryWorkshopID', :'community1ID', jsonb_build_object(
    'name', 'Workshop',
    'order', 2
));
select fx_event_category(:'eventCategoryConferenceID', :'community1ID', jsonb_build_object(
    'name', 'Conference',
    'order', 1
));
select fx_event_category(:'eventCategoryMeetupID', :'community1ID', jsonb_build_object('name', 'Meetup'));
select fx_event_category(:'eventCategorySeminarID', :'community2ID', jsonb_build_object('name', 'Seminar'));

-- Group that hosts category-counted events
select fx_group(:'groupKubernetesID', :'community1ID', :'groupCategoryTechnologyID');

-- Groups
select fx_group(:'groupDevopsID', :'community2ID', :'groupCategoryBusinessID', jsonb_build_object(
    'name', 'DevOps Vancouver',
    'slug', 'devops-vancouver'
));

-- Events counted for their categories
select fx_event(:'eventConferenceDay1ID', :'groupKubernetesID', :'eventCategoryConferenceID');
select fx_event(:'eventConferenceDay2ID', :'groupKubernetesID', :'eventCategoryConferenceID');

-- Events
select fx_event(:'eventWorkshopLabID', :'groupKubernetesID', :'eventCategoryWorkshopID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventSeminarKeynoteID', :'groupDevopsID', :'eventCategorySeminarID', jsonb_build_object('event_kind_id', 'hybrid'));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return categories for community 1 ordered by order field then name
select is(
    list_event_categories(:'community1ID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'events_count', 2,
            'event_category_id', :'eventCategoryConferenceID'::uuid,
            'name', 'Conference',
            'slug', 'conference'
        ),
        jsonb_build_object(
            'events_count', 1,
            'event_category_id', :'eventCategoryWorkshopID'::uuid,
            'name', 'Workshop',
            'slug', 'workshop'
        ),
        jsonb_build_object(
            'events_count', 0,
            'event_category_id', :'eventCategoryMeetupID'::uuid,
            'name', 'Meetup',
            'slug', 'meetup'
        )
    ),
    'Should return categories for community 1 ordered by order field then name'
);

-- Should return only categories for community 2
select is(
    list_event_categories(:'community2ID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'events_count', 1,
            'event_category_id', :'eventCategorySeminarID'::uuid,
            'name', 'Seminar',
            'slug', 'seminar'
        )
    ),
    'Should return only categories for community 2'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
