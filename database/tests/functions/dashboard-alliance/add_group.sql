-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c040000-0000-0000-0000-000000000001'
\set groupCategoryID '2c040000-0000-0000-0000-000000000002'
\set groupPrettySlugID '2c040000-0000-0000-0000-000000000003'
\set regionID '2c040000-0000-0000-0000-000000000004'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Alliance
insert into alliance (
    alliance_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, alliance_id, name)
values (:'groupCategoryID', :'allianceID', 'Technology');

-- Existing group with a pretty slug in the generated-slug space
insert into "group" (
    group_id,
    alliance_id,
    group_category_id,
    name,
    slug,
    slug_pretty
) values (
    :'groupPrettySlugID',
    :'allianceID',
    :'groupCategoryID',
    'Pretty Slug Collision Group',
    'existing-slug',
    'abc2345'
);

-- Region
insert into region (region_id, alliance_id, name)
values (:'regionID', :'allianceID', 'North America');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should create group with minimal required fields and return expected structure
select is(
    (select (
        get_group_full(
            :'allianceID'::uuid,
            add_group(
                null::uuid,
                :'allianceID'::uuid,
                jsonb_build_object(
                    'name', 'Simple Test Group',
                    'category_id', :'groupCategoryID',
                    'description', 'A simple test group',
                    'description_short', 'Brief overview of the test group'
                )
            )
        )::jsonb - 'active' - 'alliance' - 'created_at' - 'members_count' - 'group_id' - 'slug'
    )),
    format(
        '{
        "name": "Simple Test Group",
        "category": {
            "group_category_id": "%s",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A simple test group",
        "description_short": "Brief overview of the test group",
        "logo_url": "https://example.com/logo.png",
        "organizers": [],
        "sponsors": []
    }',
        :'groupCategoryID'
    )::jsonb,
    'Should create group with minimal required fields and return expected structure'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            group_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        select
            'group_added',
            null::uuid,
            null::text,
            %L::uuid,
            group_id,
            'group',
            group_id
        from "group"
        where name = 'Simple Test Group'
        $$,
        :'allianceID'
    ),
    'Should create the expected audit row'
);

-- Should auto-generate a valid slug
select ok(
    (select (
        get_group_full(
            :'allianceID'::uuid,
            add_group(
                null::uuid,
                :'allianceID'::uuid,
                jsonb_build_object(
                    'name', 'Slug Test Group',
                    'category_id', :'groupCategoryID',
                    'description', 'Testing slug generation',
                    'description_short', 'Brief'
                )
            )
        )::jsonb->>'slug'
    ) ~ '^[23456789abcdefghjkmnpqrstuvwxyz]{7}$'),
    'Should auto-generate a valid 7-character slug'
);

-- Should create group with all fields and return expected structure
select is(
    (select (
        get_group_full(
            :'allianceID'::uuid,
            add_group(
                null::uuid,
                :'allianceID'::uuid,
                format(
                    '{
                "name": "Full Test Group",
                "category_id": "%s",
                "description": "A fully populated test group",
                "description_short": "Cloud native alliance group in Seattle",
                "banner_url": "https://example.com/banner.jpg",
                "city": "San Francisco",
                "country_code": "US",
                "country_name": "United States",
                "state": "CA",
                "region_id": "%s",
                "logo_url": "https://example.com/logo.png",
                "website_url": "https://example.com",
                "bluesky_url": "https://bsky.app/profile/testgroup",
                "facebook_url": "https://facebook.com/testgroup",
                "twitter_url": "https://twitter.com/testgroup",
                "linkedin_url": "https://linkedin.com/testgroup",
                "github_url": "https://github.com/testgroup",
                "slack_url": "https://testgroup.slack.com",
                "youtube_url": "https://youtube.com/testgroup",
                "instagram_url": "https://instagram.com/testgroup",
                "flickr_url": "https://flickr.com/testgroup",
                "wechat_url": "https://wechat.com/testgroup",
                "og_image_url": "https://example.com/group-og.png",
                "tags": ["technology", "alliance", "open-source"],
                "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
                "extra_links": [{"name": "blog", "url": "https://blog.example.com"}, {"name": "docs", "url": "https://docs.example.com"}]
            }',
                    :'groupCategoryID',
                    :'regionID'
                )::jsonb
            )
        )::jsonb - 'active' - 'alliance' - 'created_at' - 'members_count' - 'group_id' - 'slug'
    )),
    format(
        '{
        "name": "Full Test Group",
        "category": {
            "group_category_id": "%s",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "description": "A fully populated test group",
        "description_short": "Cloud native alliance group in Seattle",
        "banner_url": "https://example.com/banner.jpg",
        "city": "San Francisco",
        "country_code": "US",
        "country_name": "United States",
        "state": "CA",
        "region": {
            "region_id": "%s",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "logo_url": "https://example.com/logo.png",
        "website_url": "https://example.com",
        "bluesky_url": "https://bsky.app/profile/testgroup",
        "facebook_url": "https://facebook.com/testgroup",
        "twitter_url": "https://twitter.com/testgroup",
        "linkedin_url": "https://linkedin.com/testgroup",
        "github_url": "https://github.com/testgroup",
        "slack_url": "https://testgroup.slack.com",
        "youtube_url": "https://youtube.com/testgroup",
        "instagram_url": "https://instagram.com/testgroup",
        "flickr_url": "https://flickr.com/testgroup",
        "wechat_url": "https://wechat.com/testgroup",
        "og_image_url": "https://example.com/group-og.png",
        "tags": ["technology", "alliance", "open-source"],
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "extra_links": [{"name": "blog", "url": "https://blog.example.com"}, {"name": "docs", "url": "https://docs.example.com"}],
        "organizers": [],
        "sponsors": []
    }',
        :'groupCategoryID',
        :'regionID'
    )::jsonb,
    'Should create group with all fields and return expected structure'
);

-- Should convert empty strings to null for nullable fields
select lives_ok(
    format(
        $$
        select add_group(
            null::uuid,
            %L::uuid,
            '{
        "name": "Empty String Test Group",
        "category_id": "%s",
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
        "bluesky_url": "",
        "facebook_url": "",
        "twitter_url": "",
        "linkedin_url": "",
        "github_url": "",
        "slack_url": "",
        "youtube_url": "",
        "instagram_url": "",
        "flickr_url": "",
        "wechat_url": "",
        "og_image_url": ""
            }'::jsonb
        )
        $$,
        :'allianceID',
        :'groupCategoryID'
    ),
    'Should create group with empty nullable fields'
);

select is(
    (
        select jsonb_build_object(
            'banner_url', banner_url,
            'city', city,
            'country_code', country_code,
            'country_name', country_name,
            'description', description,
            'description_short', description_short,
            'logo_url', logo_url,
            'og_image_url', og_image_url,
            'region_id', region_id,
            'state', state,
            'website_url', website_url
        )
        from "group"
        where name = 'Empty String Test Group'
    ),
    '{
        "banner_url": null,
        "city": null,
        "country_code": null,
        "country_name": null,
        "description": null,
        "description_short": null,
        "logo_url": null,
        "og_image_url": null,
        "region_id": null,
        "state": null,
        "website_url": null
    }'::jsonb,
    'Should convert empty strings to null for nullable fields'
);

-- Should retry generated slugs matching existing pretty slugs
create temporary sequence add_group_slug_test_seq;

create or replace function generate_slug(p_length int default 7)
returns text as $$
begin
    if nextval('add_group_slug_test_seq') = 1 then
        return 'abc2345';
    end if;

    return 'def6789';
end;
$$ language plpgsql;

select is(
    (
        select get_group_full(
            :'allianceID'::uuid,
            add_group(
                null::uuid,
                :'allianceID'::uuid,
                jsonb_build_object(
                    'name', 'Pretty Slug Retry Group',
                    'category_id', :'groupCategoryID',
                    'description', 'Testing pretty slug retry',
                    'description_short', 'Brief'
                )
            )
        )::jsonb->>'slug'
    ),
    'def6789',
    'Should retry generated slugs matching existing pretty slugs'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
