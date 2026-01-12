-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'

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
    banner_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner.png'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct community summary JSON
select is(
    get_community_summary(:'communityID'::uuid)::jsonb,
    '{
        "banner_url": "https://example.com/banner.png",
        "community_id": "00000000-0000-0000-0000-000000000001",
        "display_name": "Cloud Native Seattle",
        "logo_url": "https://example.com/logo.png",
        "name": "cloud-native-seattle"
    }'::jsonb,
    'Should return correct community summary data as JSON'
);

-- Should return null for non-existent community
select ok(
    get_community_summary('00000000-0000-0000-0000-000000999999'::uuid) is null,
    'Should return null for non-existent community ID'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
