-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '3a190000-0000-0000-0000-000000000001'
\set alliance2ID '3a190000-0000-0000-0000-000000000002'
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

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'alliance1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
), (
    :'alliance2ID',
    'devops-vancouver',
    'DevOps Vancouver',
    'Building DevOps expertise and alliance in Vancouver',
    'https://example.com/banner-mobile-2.png',
    'https://example.com/banner-2.png',
    'https://example.com/logo-2.png'
);

-- Group categories
insert into group_category (group_category_id, alliance_id, name)
values
    (:'groupCategoryTechnologyID', :'alliance1ID', 'Technology'),
    (:'groupCategoryBusinessID', :'alliance2ID', 'Business');

-- Event categories
insert into event_category (event_category_id, alliance_id, name, "order")
values
    (:'eventCategoryWorkshopID', :'alliance1ID', 'Workshop', 2),
    (:'eventCategoryConferenceID', :'alliance1ID', 'Conference', 1),
    (:'eventCategoryMeetupID', :'alliance1ID', 'Meetup', null),
    (:'eventCategorySeminarID', :'alliance2ID', 'Seminar', null);

-- Groups
insert into "group" (group_id, alliance_id, group_category_id, name, slug)
values
    (
        :'groupKubernetesID',
        :'alliance1ID',
        :'groupCategoryTechnologyID',
        'Kubernetes Seattle',
        'kubernetes-seattle'
    ), (
        :'groupDevopsID',
        :'alliance2ID',
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

-- Should return categories for alliance 1 ordered by order field then name
select is(
    list_event_categories(:'alliance1ID'::uuid)::jsonb,
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
    'Should return categories for alliance 1 ordered by order field then name'
);

-- Should return only categories for alliance 2
select is(
    list_event_categories(:'alliance2ID'::uuid)::jsonb,
    jsonb_build_array(
        jsonb_build_object(
            'events_count', 1,
            'event_category_id', :'eventCategorySeminarID'::uuid,
            'name', 'Seminar',
            'slug', 'seminar'
        )
    ),
    'Should return only categories for alliance 2'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
