-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set communityID '00000000-0000-0000-0000-000000000001'
\set group2ID '00000000-0000-0000-0000-000000000023'
\set group3ID '00000000-0000-0000-0000-000000000024'
\set groupDeletedID '00000000-0000-0000-0000-000000000022'
\set groupID '00000000-0000-0000-0000-000000000021'
\set nonExistentCommunityID '00000000-0000-0000-0000-000000000099'

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
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png'
);

-- Group Category
insert into group_category (group_category_id, name, community_id)
values 
    (:'category1ID', 'Technology', :'communityID'),
    (:'category2ID', 'Business', :'communityID');

-- Group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'groupID',
    'Original Group',
    'abc1234',
    :'communityID',
    :'category1ID',
    'Original description',
    '2024-01-15 10:00:00+00'
);

-- Group (deleted)
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    active,
    deleted,
    deleted_at,
    created_at
) values (
    :'groupDeletedID',
    'Deleted Group',
    'xyz9876',
    :'communityID',
    :'category1ID',
    'Deleted group description',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);

-- Group with array fields
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    tags,
    photos_urls,
    created_at
) values (
    :'group3ID'::uuid,
    'Test Group for Null Arrays',
    'mno3ghi',
    :'communityID',
    :'category1ID',
    'Has array fields',
    array['original', 'tags'],
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    '2024-01-15 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update all provided fields correctly
select update_group(
    :'communityID'::uuid,
    :'groupID'::uuid,
    '{
        "name": "Updated Group",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "description": "Updated description",
        "description_short": "Updated brief description",
        "city": "New York",
        "state": "NY",
        "country_code": "US",
        "country_name": "United States",
        "website_url": "https://updated.example.com",
        "facebook_url": "https://facebook.com/updated",
        "twitter_url": "https://twitter.com/updated",
        "tags": ["updated", "test"],
        "logo_url": "https://example.com/updated-logo.png"
    }'::jsonb
);

-- Should return expected structure after update
select is(
    (select get_group_full(:'communityID'::uuid, :'groupID'::uuid)::jsonb - 'active' - 'created_at' - 'members_count'),
    '{
        "name": "Updated Group",
        "slug": "abc1234",
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Business",
            "normalized_name": "business"
        },
        "community": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "community_id": "00000000-0000-0000-0000-000000000001",
            "display_name": "Cloud Native Seattle",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle"
        },
        "group_id": "00000000-0000-0000-0000-000000000021",
        "description": "Updated description",
        "description_short": "Updated brief description",
        "city": "New York",
        "state": "NY",
        "country_code": "US",
        "country_name": "United States",
        "website_url": "https://updated.example.com",
        "facebook_url": "https://facebook.com/updated",
        "twitter_url": "https://twitter.com/updated",
        "tags": ["updated", "test"],
        "logo_url": "https://example.com/updated-logo.png",
        "organizers": [],
        "sponsors": []
    }'::jsonb,
    'Should update all provided fields and return expected structure'
);

-- Should throw error when updating deleted group
select throws_ok(
    $$select update_group(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000022'::uuid,
        '{"name": "Won''t Work", "category_id": "00000000-0000-0000-0000-000000000011", "description": "This should fail"}'::jsonb
    )$$,
    'group not found or inactive',
    'Should throw error when trying to update deleted group'
);

-- Should convert empty strings to null for nullable fields
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    banner_url,
    city,
    state,
    country_code,
    country_name,
    website_url,
    created_at
) values (
    :'group2ID'::uuid,
    'Test Group for Empty Strings',
    'pqr4jkl',
    :'communityID',
    :'category1ID',
    'Has some values',
    'https://example.com/banner.jpg',
    'San Francisco',
    'CA',
    'US',
    'United States',
    'https://example.com',
    '2024-01-15 10:00:00+00'
);

select update_group(
    :'communityID'::uuid,
    :'group2ID'::uuid,
    '{
        "name": "Updated Group Empty Strings",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "description": "",
        "description_short": "",
        "banner_url": "",
        "city": "",
        "state": "",
        "country_code": "",
        "country_name": "",
        "website_url": "",
        "facebook_url": "",
        "twitter_url": "",
        "linkedin_url": "",
        "github_url": "",
        "slack_url": "",
        "youtube_url": "",
        "instagram_url": "",
        "flickr_url": "",
        "wechat_url": "",
        "logo_url": "",
        "region_id": ""
    }'::jsonb
);

-- Should keep minimal fields after empty-string conversion
select is(
    (select get_group_full(:'communityID'::uuid, :'group2ID'::uuid)::jsonb - 'active' - 'group_id' - 'created_at' - 'members_count' - 'category' - 'community' - 'organizers' - 'sponsors'),
    '{
        "name": "Updated Group Empty Strings",
        "slug": "pqr4jkl"
    }'::jsonb,
    'Should convert empty strings to null for nullable fields'
);

-- Should throw error when community_id mismatches
select throws_ok(
    $$select update_group(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000021'::uuid,
        '{"name": "Won''t Work", "category_id": "00000000-0000-0000-0000-000000000011", "description": "This should fail"}'::jsonb
    )$$,
    'group not found or inactive',
    'Should throw error when community_id does not match'
);

-- Should handle explicit null values for array fields
select update_group(
    :'communityID'::uuid,
    :'group3ID'::uuid,
    '{
        "name": "Updated Group Null Arrays",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "description": "Updated description",
        "tags": null,
        "photos_urls": null
    }'::jsonb
);

-- Should persist explicit null arrays in result
select is(
    (select get_group_full(:'communityID'::uuid, :'group3ID'::uuid)::jsonb - 'active' - 'group_id' - 'created_at' - 'members_count' - 'category' - 'community' - 'organizers' - 'sponsors'),
    '{
        "name": "Updated Group Null Arrays",
        "slug": "mno3ghi",
        "description": "Updated description"
    }'::jsonb,
    'Should handle explicit null values for array fields (tags, photos_urls)'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
