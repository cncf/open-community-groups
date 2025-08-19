-- Start transaction and plan tests
begin;
select plan(3);

-- Variables
\set community1ID '00000000-0000-0000-0000-000000000001'
\set category1ID '00000000-0000-0000-0000-000000000011'
\set region1ID '00000000-0000-0000-0000-000000000012'

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

-- Seed region
insert into region (region_id, name, community_id)
values (:'region1ID', 'North America', :'community1ID');

-- Seed group category
insert into group_category (group_category_id, name, community_id)
values (:'category1ID', 'Technology', :'community1ID');

-- Test: add_group function creates group with required fields only
select is(
    (select (get_group_full(
        add_group(
            :'community1ID'::uuid,
            '{"name": "Simple Test Group", "slug": "simple-test-group", "category_id": "00000000-0000-0000-0000-000000000011", "description": "A simple test group"}'::jsonb
        )
    )::jsonb - 'created_at' - 'members_count' - 'group_id')),
    '{
        "name": "Simple Test Group",
        "slug": "simple-test-group",
        "category": {
            "category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A simple test group",
        "organizers": []
    }'::jsonb,
    'add_group should create group with minimal required fields and return expected structure'
);

-- Test: add_group function creates group with all fields
select is(
    (select (get_group_full(
        add_group(
            :'community1ID'::uuid,
            '{
                "name": "Full Test Group",
                "slug": "full-test-group",
                "category_id": "00000000-0000-0000-0000-000000000011",
                "description": "A fully populated test group",
                "banner_url": "https://example.com/banner.jpg",
                "city": "San Francisco",
                "country_code": "US",
                "country_name": "United States",
                "state": "CA",
                "region_id": "00000000-0000-0000-0000-000000000012",
                "logo_url": "https://example.com/logo.png",
                "website_url": "https://example.com",
                "facebook_url": "https://facebook.com/testgroup",
                "twitter_url": "https://twitter.com/testgroup",
                "linkedin_url": "https://linkedin.com/testgroup",
                "github_url": "https://github.com/testgroup",
                "slack_url": "https://testgroup.slack.com",
                "youtube_url": "https://youtube.com/testgroup",
                "instagram_url": "https://instagram.com/testgroup",
                "flickr_url": "https://flickr.com/testgroup",
                "wechat_url": "https://wechat.com/testgroup",
                "tags": ["technology", "community", "open-source"],
                "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
                "extra_links": [{"name": "blog", "url": "https://blog.example.com"}, {"name": "docs", "url": "https://docs.example.com"}]
            }'::jsonb
        )
    )::jsonb - 'created_at' - 'members_count' - 'group_id')),
    '{
        "name": "Full Test Group",
        "slug": "full-test-group",
        "category": {
            "category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A fully populated test group",
        "banner_url": "https://example.com/banner.jpg",
        "city": "San Francisco",
        "country_code": "US",
        "country_name": "United States",
        "state": "CA",
        "region": {
            "region_id": "00000000-0000-0000-0000-000000000012",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "logo_url": "https://example.com/logo.png",
        "website_url": "https://example.com",
        "facebook_url": "https://facebook.com/testgroup",
        "twitter_url": "https://twitter.com/testgroup",
        "linkedin_url": "https://linkedin.com/testgroup",
        "github_url": "https://github.com/testgroup",
        "slack_url": "https://testgroup.slack.com",
        "youtube_url": "https://youtube.com/testgroup",
        "instagram_url": "https://instagram.com/testgroup",
        "flickr_url": "https://flickr.com/testgroup",
        "wechat_url": "https://wechat.com/testgroup",
        "tags": ["technology", "community", "open-source"],
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "extra_links": [{"name": "blog", "url": "https://blog.example.com"}, {"name": "docs", "url": "https://docs.example.com"}],
        "organizers": []
    }'::jsonb,
    'add_group should create group with all fields and return expected structure'
);

-- Test: add_group function converts empty strings to null for nullable fields
do $$
declare
    v_group_id uuid;
begin
    v_group_id := add_group(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '{
            "name": "Empty String Test Group",
            "slug": "empty-string-test-group-unique",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "description": "",
            "banner_url": "",
            "city": "",
            "country_code": "",
            "country_name": "",
            "state": "",
            "region_id": "",
            "logo_url": "",
            "website_url": "",
            "facebook_url": "",
            "twitter_url": "",
            "linkedin_url": "",
            "github_url": "",
            "slack_url": "",
            "youtube_url": "",
            "instagram_url": "",
            "flickr_url": "",
            "wechat_url": ""
        }'::jsonb
    );
end $$;

select is(
    (select row_to_json(t.*)::jsonb - 'group_id' - 'created_at' - 'active' - 'deleted' - 'tsdoc' - 'community_id' - 'group_site_layout_id' - 'group_category_id' - 'deleted_at' - 'location' 
     from (
        select * from "group" 
        where slug = 'empty-string-test-group-unique'
     ) t),
    '{
        "name": "Empty String Test Group",
        "slug": "empty-string-test-group-unique",
        "description": null,
        "banner_url": null,
        "city": null,
        "country_code": null,
        "country_name": null,
        "state": null,
        "region_id": null,
        "logo_url": null,
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
        "extra_links": null,
        "photos_urls": null,
        "tags": null
    }'::jsonb,
    'add_group should convert empty strings to null for nullable fields'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;