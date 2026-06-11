-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a0c0000-0000-0000-0000-000000000001'
\set eventCategoryID '3a0c0000-0000-0000-0000-000000000002'
\set eventID '3a0c0000-0000-0000-0000-000000000003'
\set groupCategoryID '3a0c0000-0000-0000-0000-000000000004'
\set groupID '3a0c0000-0000-0000-0000-000000000005'
\set sponsorID '3a0c0000-0000-0000-0000-000000000006'

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
    :'communityID',
    'cloud-native-london',
    'Cloud Native London',
    'Community for cloud native technologies in London',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Conference');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'Group London', 'group-london');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values (:'sponsorID', :'groupID', 'Kappa', 'https://ex.com/kappa.png', null);

-- Event
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
values (
    :'eventID',
    :'eventCategoryID',
    (select event_kind_id from event_kind limit 1),
    :'groupID',
    'Event 1',
    'event-1',
    'desc',
    'UTC'
);

-- Event references sponsor
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'eventID', :'sponsorID', 'Gold');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should fail when sponsor is referenced by event
select throws_like(
    format(
        $$select delete_group_sponsor(null::uuid, %L::uuid, %L::uuid)$$,
        :'groupID', :'sponsorID'
    ),
    '%sponsor is used by one or more events%',
    'Should fail when sponsor is referenced by event'
);

-- Remove reference and try again
delete from event_sponsor where group_sponsor_id = :'sponsorID'::uuid;

-- Should remove sponsor when unreferenced
select lives_ok(
    format(
        $$select delete_group_sponsor(null::uuid, %L::uuid, %L::uuid)$$,
        :'groupID', :'sponsorID'
    ),
    'Should delete the sponsor without error once unreferenced'
);

select is(
    (select count(*) from group_sponsor where group_sponsor_id = :'sponsorID'::uuid),
    0::bigint,
    'Should remove sponsor'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'group_sponsor_deleted',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            'group_sponsor',
            %L::uuid
        )
        $$,
        :'communityID', :'groupID', :'sponsorID'
    ),
    'Should create the expected audit row'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
