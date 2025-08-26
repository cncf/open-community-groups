-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set community1ID '00000000-0000-0000-0000-000000000001'
\set community2ID '00000000-0000-0000-0000-000000000002'
\set groupID '00000000-0000-0000-0000-000000000021'
\set userOrganizerID '00000000-0000-0000-0000-000000000011'
\set userRegularID '00000000-0000-0000-0000-000000000012'
\set categoryID '00000000-0000-0000-0000-000000000031'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- First community for testing group ownership
insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'community1ID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'test.example.com',
    'Seattle community for cloud native technologies',
    'https://example.com/logo.png',
    '{}'::jsonb,
    'Cloud Native Seattle Community'
);

-- Second community for cross-community ownership testing

insert into community (
    community_id,
    name,
    display_name,
    host,
    description,
    header_logo_url,
    theme,
    title
) values (
    :'community2ID',
    'cloud-native-portland',
    'Cloud Native Portland',
    'test2.example.com',
    'Portland community for cloud native technologies',
    'https://example.com/logo2.png',
    '{}'::jsonb,
    'Cloud Native Portland Community'
);

-- Users with different permission levels
-- userOrganizerID: User with group organizer role
-- userRegularID: Regular user without special permissions
insert into "user" (
    user_id,
    auth_hash,
    community_id,
    email,
    email_verified,
    name,
    username
) values (
    :'userOrganizerID',
    gen_random_bytes(32),
    :'community1ID',
    'organizer@example.com',
    true,
    'Group Organizer',
    'grouporganizer'
), (
    :'userRegularID',
    gen_random_bytes(32),
    :'community1ID',
    'regular@example.com',
    true,
    'Regular User',
    'regularuser'
);

-- Group category for test group
insert into group_category (
    group_category_id,
    community_id,
    name
) values (
    :'categoryID',
    :'community1ID',
    'Technology'
);

-- Test group for ownership verification
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,
    description
) values (
    :'groupID',
    :'community1ID',
    :'categoryID',
    'Kubernetes Study Group',
    'kubernetes-study',
    'Weekly Kubernetes study and discussion group'
);

-- Group team membership (grants ownership to organizer)
insert into group_team (
    group_id,
    user_id,
    role
) values (
    :'groupID',
    :'userOrganizerID',
    'Organizer'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- User in group_team should own the group
select ok(
    user_owns_group(:'community1ID', :'groupID', :'userOrganizerID'),
    'User in group_team should own the group'
);

-- User not in group_team should not own the group
select ok(
    not user_owns_group(:'community1ID', :'groupID', :'userRegularID'),
    'User not in group_team should not own the group'
);

-- Non-existent user should not own the group
select ok(
    not user_owns_group(:'community1ID', :'groupID', '00000000-0000-0000-0000-000000000099'::uuid),
    'Non-existent user should not own the group'
);

-- Cross-community check should fail even for group owner
select ok(
    not user_owns_group(:'community2ID', :'groupID', :'userOrganizerID'),
    'Cross-community ownership check should fail even for actual group owner'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
