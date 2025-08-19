-- Start transaction and plan tests
begin;
select plan(4);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set category2ID '00000000-0000-0000-0000-000000000012'
\set group1ID '00000000-0000-0000-0000-000000000021'
\set groupDeletedID '00000000-0000-0000-0000-000000000022'
\set group2ID '00000000-0000-0000-0000-000000000023'

-- Seed community
insert into community (
    community_id,
    name,
    display_name,
    host,
    title,
    description,
    header_logo_url,
    theme
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'test.localhost',
    'Test Community Title',
    'A test community for testing purposes',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Seed group categories
insert into group_category (group_category_id, name, community_id)
values 
    (:'category1ID', 'Technology', :'community1ID'),
    (:'category2ID', 'Business', :'community1ID');

-- Seed active group
insert into "group" (
    group_id,
    name,
    slug,
    community_id,
    group_category_id,
    description,
    created_at
) values (
    :'group1ID',
    'Original Group',
    'original-group',
    :'community1ID',
    :'category1ID',
    'Original description',
    '2024-01-15 10:00:00+00'
);

-- Seed deleted group
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
    'deleted-group',
    :'community1ID',
    :'category1ID',
    'Deleted group description',
    false,
    true,
    '2024-02-15 10:00:00+00',
    '2024-01-15 10:00:00+00'
);

-- Test: update_group function updates group fields correctly
select update_group(
    :'community1ID'::uuid,
    :'group1ID'::uuid,
    '{
        "name": "Updated Group",
        "slug": "updated-group",
        "category_id": "00000000-0000-0000-0000-000000000012",
        "description": "Updated description",
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

select is(
    (select get_group_full(:'group1ID'::uuid)::jsonb - 'created_at' - 'members_count'),
    '{
        "name": "Updated Group",
        "slug": "updated-group",
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000012",
            "name": "Business",
            "normalized_name": "business"
        },
        "group_id": "00000000-0000-0000-0000-000000000021",
        "description": "Updated description",
        "city": "New York",
        "state": "NY",
        "country_code": "US",
        "country_name": "United States",
        "website_url": "https://updated.example.com",
        "facebook_url": "https://facebook.com/updated",
        "twitter_url": "https://twitter.com/updated",
        "tags": ["updated", "test"],
        "logo_url": "https://example.com/updated-logo.png",
        "organizers": []
    }'::jsonb,
    'update_group should update all provided fields and return expected structure'
);

-- Test: update_group throws error for deleted group
select throws_ok(
    $$select update_group(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '00000000-0000-0000-0000-000000000022'::uuid,
        '{"name": "Won''t Work", "slug": "wont-work", "category_id": "00000000-0000-0000-0000-000000000011", "description": "This should fail"}'::jsonb
    )$$,
    'P0001',
    'group not found',
    'update_group should throw error when trying to update deleted group'
);

-- Test: update_group converts empty strings to null for nullable fields
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
    'test-group-empty-strings',
    :'community1ID',
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
    :'community1ID'::uuid,
    :'group2ID'::uuid,
    '{
        "name": "Updated Group Empty Strings",
        "slug": "updated-group-empty-strings",
        "category_id": "00000000-0000-0000-0000-000000000011",
        "description": "",
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

select is(
    (select row_to_json(t.*)::jsonb - 'group_id' - 'created_at' - 'active' - 'deleted' - 'tsdoc' - 'community_id' - 'group_site_layout_id' - 'group_category_id' - 'deleted_at' - 'location'
     from (
        select * from "group" where group_id = :'group2ID'::uuid
     ) t),
    '{
        "name": "Updated Group Empty Strings",
        "slug": "updated-group-empty-strings",
        "description": null,
        "banner_url": null,
        "city": null,
        "state": null,
        "country_code": null,
        "country_name": null,
        "website_url": null,
        "facebook_url": null,
        "twitter_url": null,
        "linkedin_url": null,
        "github_url": null,
        "slack_url": null,
        "youtube_url": null,
        "instagram_url": null,
        "flickr_url": null,
        "wechat_url": null,
        "logo_url": null,
        "region_id": null,
        "extra_links": null,
        "photos_urls": null,
        "tags": null
    }'::jsonb,
    'update_group should convert empty strings to null for nullable fields'
);

-- Test: update_group throws error for wrong community_id
select throws_ok(
    $$select update_group(
        '00000000-0000-0000-0000-000000000099'::uuid,
        '00000000-0000-0000-0000-000000000021'::uuid,
        '{"name": "Won''t Work", "slug": "wont-work", "category_id": "00000000-0000-0000-0000-000000000011", "description": "This should fail"}'::jsonb
    )$$,
    'P0001',
    'group not found',
    'update_group should throw error when community_id does not match'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;