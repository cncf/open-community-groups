-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alliance1ID '00000000-0000-0000-0000-000000000001'
\set alliance2ID '00000000-0000-0000-0000-000000000002'
\set user1ID '00000000-0000-0000-0000-000000000011'
\set user2ID '00000000-0000-0000-0000-000000000012'
\set user3ID '00000000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliances
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    logo_url,
    banner_mobile_url,
    banner_url
) values
    (:'alliance1ID', 'alpha-alliance', 'Alpha Alliance', 'First alliance', 'https://example.com/alpha.png', 'https://example.com/alpha-banner_mobile.png', 'https://example.com/alpha-banner.png'),
    (:'alliance2ID', 'beta-alliance', 'Beta Alliance', 'Second alliance', 'https://example.com/beta.png', 'https://example.com/beta-banner_mobile.png', 'https://example.com/beta-banner.png');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    name,
    username,
    email_verified
) values
    (:'user1ID', gen_random_bytes(32), 'alice@example.com', 'Alice', 'alice', true),
    (:'user2ID', gen_random_bytes(32), 'bob@example.com', 'Bob', 'bob', true),
    (:'user3ID', gen_random_bytes(32), 'charlie@example.com', 'Charlie', 'charlie', true);

-- Team memberships
-- User 1 is team member of both alliances (accepted)
-- User 2 is team member of alliance1 only (accepted)
-- User 3 is pending team member of alliance1 (not accepted)
insert into alliance_team (accepted, alliance_id, role, user_id) values
    (true, :'alliance1ID', 'admin', :'user1ID'),
    (true, :'alliance2ID', 'admin', :'user1ID'),
    (true, :'alliance1ID', 'admin', :'user2ID'),
    (false, :'alliance1ID', 'viewer', :'user3ID');

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
    list_user_alliances('00000000-0000-0000-0000-000000000099'::uuid)::text,
    '[]',
    'Should return empty array for unknown user'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
