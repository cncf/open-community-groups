-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'
\set groupID '00000000-0000-0000-0000-000000000011'
\set eventID '00000000-0000-0000-0000-000000000012'
\set inUseCategoryID '00000000-0000-0000-0000-000000000013'
\set unusedCategoryID '00000000-0000-0000-0000-000000000014'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values (
    :'communityID',
    'cncf-seattle',
    'CNCF Seattle',
    'Community for event category delete tests',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (
    community_id,
    group_category_id,
    name
) values (
    :'communityID',
    :'groupCategoryID',
    'Platform'
);

-- Group
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Seattle Platform',
    'seattle-platform'
);

-- Event categories
insert into event_category (
    community_id,
    event_category_id,
    name
) values
    (:'communityID', :'inUseCategoryID', 'Meetup'),
    (:'communityID', :'unusedCategoryID', 'Webinar');

-- Event using the first category
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Test event',
    :'inUseCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Monthly Meetup',
    'monthly-meetup',
    'UTC'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should block deleting category that is still referenced by events
select throws_ok(
    $$ select delete_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000013'::uuid
    ) $$,
    'cannot delete event category in use by events',
    'Should block deleting event category referenced by events'
);

-- Should delete event category with no event references
select lives_ok(
    $$ select delete_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000014'::uuid
    ) $$,
    'Should delete an unused event category'
);
select results_eq(
    $$
    select count(*)::bigint
    from event_category ec
    where ec.event_category_id = '00000000-0000-0000-0000-000000000014'::uuid
    $$,
    $$ values (0::bigint) $$,
    'Unused event category should be deleted'
);

-- Should fail when target category does not exist
select throws_ok(
    $$ select delete_event_category(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000099'::uuid
    ) $$,
    'event category not found',
    'Should fail when deleting a non-existing event category'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
