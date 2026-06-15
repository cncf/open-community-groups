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

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'community2ID',
    'devops-vancouver',
    'DevOps Vancouver',
    'Building DevOps expertise and community in Vancouver',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
);

-- Group categories
insert into group_category (group_category_id, community_id, name)
values
    (:'groupCategoryTechnologyID', :'community1ID', 'Technology'),
    (:'groupCategoryBusinessID', :'community2ID', 'Business');

-- Event categories
insert into event_category (event_category_id, community_id, name, "order")
values
    (:'eventCategoryWorkshopID', :'community1ID', 'Workshop', 2),
    (:'eventCategoryConferenceID', :'community1ID', 'Conference', 1),
    (:'eventCategoryMeetupID', :'community1ID', 'Meetup', null),
    (:'eventCategorySeminarID', :'community2ID', 'Seminar', null);

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug)
values
    (
        :'groupKubernetesID',
        :'community1ID',
        :'groupCategoryTechnologyID',
        'Kubernetes Seattle',
        'kubernetes-seattle'
    ), (
        :'groupDevopsID',
        :'community2ID',
        :'groupCategoryBusinessID',
        'DevOps Vancouver',
        'devops-vancouver'
    );

-- Events
insert into event (
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone
)
values
    (
        :'eventConferenceDay1ID',
        :'eventCategoryConferenceID',
        'in-person',
        :'groupKubernetesID',
        'Conference Day 1',
        'conference-day-1',
        'Conference opening day',
        'UTC'
    ),
    (
        :'eventConferenceDay2ID',
        :'eventCategoryConferenceID',
        'in-person',
        :'groupKubernetesID',
        'Conference Day 2',
        'conference-day-2',
        'Conference deep-dive sessions',
        'UTC'
    ),
    (
        :'eventWorkshopLabID',
        :'eventCategoryWorkshopID',
        'virtual',
        :'groupKubernetesID',
        'Workshop Lab',
        'workshop-lab',
        'Workshop hands-on labs',
        'UTC'
    ),
    (
        :'eventSeminarKeynoteID',
        :'eventCategorySeminarID',
        'hybrid',
        :'groupDevopsID',
        'Seminar Keynote',
        'seminar-keynote',
        'Seminar keynote',
        'UTC'
    );

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
