-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '30000000-0000-0000-0000-000000000010'
\set communityID '30000000-0000-0000-0000-000000000001'
\set groupID     '30000000-0000-0000-0000-000000000002'
\set sponsorID   '30000000-0000-0000-0000-000000000003'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (community_id, name, display_name, description, logo_url, banner_mobile_url, banner_url)
values (:'communityID', 'cloud-native-paris', 'Cloud Native Paris', 'Community for cloud native technologies in Paris', 'https://example.com/logo.png', 'https://example.com/banner_mobile.png', 'https://example.com/banner.png');

-- Group Category (required by group)
insert into group_category (group_category_id, name, community_id)
values ('30000000-0000-0000-0000-000000000011', 'Tech', :'communityID');

-- Group
insert into "group" (group_id, community_id, name, slug, group_category_id)
values (:'groupID', :'communityID', 'Group Paris', 'group-paris', '30000000-0000-0000-0000-000000000011');

-- Sponsor
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url, featured)
values (:'sponsorID', :'groupID', 'Iota', 'https://ex.com/iota.png', null, false);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update the featured flag to true
select lives_ok(
    $$select update_group_sponsor_featured(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '30000000-0000-0000-0000-000000000002'::uuid,
        '30000000-0000-0000-0000-000000000003'::uuid,
        true
    )$$,
    'Should update the featured flag to true'
);
select results_eq(
    $$select featured from group_sponsor where group_sponsor_id = '30000000-0000-0000-0000-000000000003'::uuid$$,
    $$values (true)$$,
    'Should persist the updated featured flag'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            community_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
        order by created_at asc
    $$,
    $$
        values (
            'group_sponsor_updated',
            '30000000-0000-0000-0000-000000000010'::uuid,
            '30000000-0000-0000-0000-000000000001'::uuid,
            '30000000-0000-0000-0000-000000000002'::uuid,
            'group_sponsor',
            '30000000-0000-0000-0000-000000000003'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should update the featured flag back to false
select lives_ok(
    $$select update_group_sponsor_featured(
        '30000000-0000-0000-0000-000000000010'::uuid,
        '30000000-0000-0000-0000-000000000002'::uuid,
        '30000000-0000-0000-0000-000000000003'::uuid,
        false
    )$$,
    'Should update the featured flag to false'
);
select results_eq(
    $$select featured from group_sponsor where group_sponsor_id = '30000000-0000-0000-0000-000000000003'::uuid$$,
    $$values (false)$$,
    'Should persist the featured flag when disabling it'
);

-- Should create another audit row for the second update
select results_eq(
    $$select count(*) from audit_log$$,
    $$values (2::bigint)$$,
    'Should create an audit row for each featured flag update'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
