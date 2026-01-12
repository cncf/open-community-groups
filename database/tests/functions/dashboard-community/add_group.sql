-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set categoryID '00000000-0000-0000-0000-000000000011'
\set communityID '00000000-0000-0000-0000-000000000001'
\set regionID '00000000-0000-0000-0000-000000000012'

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

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values (:'categoryID', 'Technology', :'communityID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create group with minimal required fields and return expected structure
select is(
    (select (
        get_group_full(
            :'communityID'::uuid,
            add_group(
                :'communityID'::uuid,
                '{"name": "Simple Test Group", "category_id": "00000000-0000-0000-0000-000000000011", "description": "A simple test group", "description_short": "Brief overview of the test group"}'::jsonb
            )
        )::jsonb - 'active' - 'community' - 'created_at' - 'members_count' - 'group_id' - 'slug'
    )),
    '{
        "name": "Simple Test Group",
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A simple test group",
        "description_short": "Brief overview of the test group",
        "organizers": [],
        "sponsors": []
    }'::jsonb,
    'Should create group with minimal required fields and return expected structure'
);

-- Should auto-generate a valid slug
select ok(
    (select (
        get_group_full(
            :'communityID'::uuid,
            add_group(
                :'communityID'::uuid,
                '{"name": "Slug Test Group", "category_id": "00000000-0000-0000-0000-000000000011", "description": "Testing slug generation", "description_short": "Brief"}'::jsonb
            )
        )::jsonb->>'slug'
    ) ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{7}$'),
    'Should auto-generate a valid 7-character slug'
);

-- Should create group with all fields and return expected structure
select is(
    (select (
        get_group_full(
            :'communityID'::uuid,
            add_group(
                :'communityID'::uuid,
                '{
                "name": "Full Test Group",
                "category_id": "00000000-0000-0000-0000-000000000011",
                "description": "A fully populated test group",
                "description_short": "Cloud native community group in Seattle",
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
        )::jsonb - 'active' - 'community' - 'created_at' - 'members_count' - 'group_id' - 'slug'
    )),
    '{
        "name": "Full Test Group",
        "category": {
            "group_category_id": "00000000-0000-0000-0000-000000000011",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A fully populated test group",
        "description_short": "Cloud native community group in Seattle",
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
        "organizers": [],
        "sponsors": []
    }'::jsonb,
    'Should create group with all fields and return expected structure'
);

-- Should convert empty strings to null for nullable fields
do $$
declare
    v_group_id uuid;
    v_group_record record;
begin
    v_group_id := add_group(
        '00000000-0000-0000-0000-000000000001'::uuid,
        '{
            "name": "Empty String Test Group",
            "category_id": "00000000-0000-0000-0000-000000000011",
            "description": "",
            "description_short": "",
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

    select * into v_group_record from "group" where group_id = v_group_id;

    -- Verify nullable fields are null
    if v_group_record.description is not null
       or v_group_record.description_short is not null
       or v_group_record.banner_url is not null
       or v_group_record.city is not null
       or v_group_record.country_code is not null
       or v_group_record.country_name is not null
       or v_group_record.state is not null
       or v_group_record.region_id is not null
       or v_group_record.logo_url is not null
       or v_group_record.website_url is not null
    then
        raise exception 'Empty strings should be converted to null';
    end if;
end $$;

select pass('Should convert empty strings to null for nullable fields');

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
