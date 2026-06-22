-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '2c130000-0000-0000-0000-000000000001'
\set alliance2ID '2c130000-0000-0000-0000-000000000002'
\set unknownUserID '2c130000-0000-0000-0000-000000000003'
\set user1ID '2c130000-0000-0000-0000-000000000004'
\set user2ID '2c130000-0000-0000-0000-000000000005'
\set user3ID '2c130000-0000-0000-0000-000000000006'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
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
    'alpha-alliance',
    'Alpha Alliance',
    'First alliance',
    'https://example.com/alpha-banner-mobile.png',
    'https://example.com/alpha-banner.png',
    'https://example.com/alpha.png'
), (
    :'alliance2ID',
    'beta-alliance',
    'Beta Alliance',
    'Second alliance',
    'https://example.com/beta-banner-mobile.png',
    'https://example.com/beta-banner.png',
    'https://example.com/beta.png'
);

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', true, 'alice', 'Alice'),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', true, 'bob', 'Bob'),
    (:'user3ID', gen_random_bytes(32), 'charlie@example.com', true, 'charlie', 'Charlie');

-- Team memberships
-- User 1 is team member of both alliances (accepted)
-- User 2 is team member of alliance1 only (accepted)
-- User 3 is pending team member of alliance1 (not accepted)
insert into alliance_team (alliance_id, user_id, accepted, role) values
    (:'alliance1ID', :'user1ID', true, 'admin'),
    (:'alliance2ID', :'user1ID', true, 'admin'),
    (:'alliance1ID', :'user2ID', true, 'admin'),
    (:'alliance1ID', :'user3ID', false, 'viewer');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return alliances for user who is team member of multiple alliances
select is(
    list_user_alliances(:'user1ID'::uuid)::jsonb,
    (select json_agg(get_alliance_summary(alliance_id) order by name) from alliance)::jsonb,
    'Should return alliances in alphabetical order for user in multiple alliances'
);

-- Should return single alliance for user who is team member of one alliance
select is(
    list_user_alliances(:'user2ID'::uuid)::jsonb,
    json_build_array(get_alliance_summary(:'alliance1ID'::uuid))::jsonb,
    'Should return single alliance for user in one alliance'
);

-- Should return empty array for user with pending (not accepted) invitation
select is(
    list_user_alliances(:'user3ID'::uuid)::text,
    '[]',
    'Should return empty array for user with pending invitation'
);

-- Should return empty array for unknown user
select is(
    list_user_alliances(:'unknownUserID'::uuid)::text,
    '[]',
    'Should return empty array for unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
