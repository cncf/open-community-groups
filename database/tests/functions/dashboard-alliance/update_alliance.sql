-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allianceID '2c140000-0000-0000-0000-000000000001'
\set unknownAllianceID '2c140000-0000-0000-0000-000000000002'

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
    logo_url,
    active,
    ad_banner_link_url,
    ad_banner_url,
    bluesky_url,
    alliance_site_layout_id,
    extra_links,
    facebook_url,
    flickr_url,
    github_url,
    instagram_url,
    linkedin_url,
    new_group_details,
    photos_urls,
    slack_url,
    twitter_url,
    website_url,
    wechat_url,
    youtube_url
) values (
    :'allianceID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant alliance for cloud native technologies and practices in Seattle',
    'https://original.com/alliance-banner-mobile.png',
    'https://original.com/alliance-banner.png',
    'https://original.com/logo.png',
    true,
    'https://original.com/banner-link',
    'https://original.com/banner.png',
    'https://bsky.app/profile/original',
    'default',
    '{"docs": "https://docs.original.com"}'::jsonb,
    'https://facebook.com/original',
    'https://flickr.com/original',
    'https://github.com/original',
    'https://instagram.com/original',
    'https://linkedin.com/original',
    'Contact team members to create groups',
    array['https://original.com/photo1.jpg', 'https://original.com/photo2.jpg'],
    'https://original.slack.com',
    'https://twitter.com/original',
    'https://original.com',
    'https://wechat.com/original',
    'https://youtube.com/original'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update required fields and set optional fields to null when not provided
select lives_ok(
    format(
        $$select update_alliance(
        null::uuid,
        %L::uuid,
        '{
            "description": "Updated description for Seattle cloud native alliance",
            "display_name": "Cloud Native Seattle Updated",
            "logo_url": "https://updated.com/logo.png"
        }'::jsonb
    )$$,
        :'allianceID'
    ),
    'Should execute update with only required fields'
);

select is(
    (select get_alliance_full(:'allianceID'::uuid)::jsonb - 'alliance_id' - 'created_at'),
    '{
        "active": true,
        "banner_mobile_url": "https://original.com/alliance-banner-mobile.png",
        "banner_url": "https://original.com/alliance-banner.png",
        "alliance_site_layout_id": "default",
        "coffee_meet_enabled": true,
        "description": "Updated description for Seattle cloud native alliance",
        "display_name": "Cloud Native Seattle Updated",
        "group_team_management_restricted": false,
        "logo_url": "https://updated.com/logo.png",
        "name": "cloud-native-seattle"
    }'::jsonb,
    'Should persist required fields and clear omitted optional fields'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            alliance_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    format(
        $$
        values (
            'alliance_updated',
            null::uuid,
            null::text,
            %L::uuid,
            'alliance',
            %L::uuid
        )
        $$,
        :'allianceID',
        :'allianceID'
    ),
    'Should create the expected audit row'
);

-- Should update all fields including optional ones
select lives_ok(
    format(
        $$select update_alliance(
        null::uuid,
        %L::uuid,
        '{
            "description": "Comprehensive cloud native alliance in Seattle",
            "display_name": "Cloud Native Seattle Complete",
            "logo_url": "https://new.com/logo.png",
            "ad_banner_url": "https://new.com/banner.png",
            "ad_banner_link_url": "https://new.com/link",
            "banner_mobile_url": "https://new.com/alliance-banner_mobile.png",
            "banner_url": "https://new.com/alliance-banner.png",
            "bluesky_url": "https://bsky.app/profile/new",
            "coffee_meet_enabled": false,
            "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
            "facebook_url": "https://facebook.com/new",
            "flickr_url": "https://flickr.com/new",
            "github_url": "https://github.com/new",
            "group_team_management_restricted": true,
            "instagram_url": "https://instagram.com/new",
            "linkedin_url": "https://linkedin.com/new",
            "new_group_details": "New groups welcome!",
            "og_image_url": "https://new.com/og-image.png",
            "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
            "slack_url": "https://new.slack.com",
            "twitter_url": "https://twitter.com/new",
            "website_url": "https://new.com",
            "wechat_url": "https://wechat.com/new",
            "youtube_url": "https://youtube.com/new"
        }'::jsonb
    )$$,
        :'allianceID'
    ),
    'Should update all fields including optional ones'
);

select is(
    (select get_alliance_full(:'allianceID'::uuid)::jsonb - 'alliance_id' - 'created_at'),
    '{
        "active": true,
        "ad_banner_link_url": "https://new.com/link",
        "ad_banner_url": "https://new.com/banner.png",
        "banner_mobile_url": "https://new.com/alliance-banner_mobile.png",
        "banner_url": "https://new.com/alliance-banner.png",
        "bluesky_url": "https://bsky.app/profile/new",
        "alliance_site_layout_id": "default",
        "coffee_meet_enabled": false,
        "description": "Comprehensive cloud native alliance in Seattle",
        "display_name": "Cloud Native Seattle Complete",
        "extra_links": {"blog": "https://blog.new.com", "forum": "https://forum.new.com"},
        "facebook_url": "https://facebook.com/new",
        "flickr_url": "https://flickr.com/new",
        "github_url": "https://github.com/new",
        "group_team_management_restricted": true,
        "instagram_url": "https://instagram.com/new",
        "linkedin_url": "https://linkedin.com/new",
        "logo_url": "https://new.com/logo.png",
        "name": "cloud-native-seattle",
        "new_group_details": "New groups welcome!",
        "og_image_url": "https://new.com/og-image.png",
        "photos_urls": ["https://new.com/p1.jpg", "https://new.com/p2.jpg", "https://new.com/p3.jpg"],
        "slack_url": "https://new.slack.com",
        "twitter_url": "https://twitter.com/new",
        "website_url": "https://new.com",
        "wechat_url": "https://wechat.com/new",
        "youtube_url": "https://youtube.com/new"
    }'::jsonb,
    'Should update all fields correctly including optional ones'
);

-- Should convert empty strings to null for nullable fields
select lives_ok(
    format(
        $$select update_alliance(
        null::uuid,
        %L::uuid,
        '{
            "ad_banner_url": "",
            "ad_banner_link_url": "",
            "bluesky_url": "",
            "facebook_url": "",
            "flickr_url": "",
            "github_url": "",
            "instagram_url": "",
            "linkedin_url": "",
            "new_group_details": "",
            "og_image_url": "",
            "slack_url": "",
            "twitter_url": "",
            "website_url": "",
            "wechat_url": "",
            "youtube_url": ""
        }'::jsonb
    )$$,
        :'allianceID'
    ),
    'Should execute update converting empty strings to null'
);

select is(
    (select row_to_json(t.*)::jsonb - 'alliance_id' - 'created_at' - 'active' - 'banner_mobile_url' - 'banner_url' - 'alliance_site_layout_id' - 'description' - 'display_name' - 'logo_url' - 'name' - 'extra_links' - 'photos_urls'
     from (
        select * from alliance where alliance_id = :'allianceID'::uuid
     ) t),
    '{
        "ad_banner_url": null,
        "ad_banner_link_url": null,
        "bluesky_url": null,
        "coffee_meet_enabled": false,
        "facebook_url": null,
        "flickr_url": null,
        "github_url": null,
        "group_team_management_restricted": true,
        "instagram_url": null,
        "linkedin_url": null,
        "new_group_details": null,
        "og_image_url": null,
        "slack_url": null,
        "twitter_url": null,
        "website_url": null,
        "wechat_url": null,
        "youtube_url": null
    }'::jsonb,
    'Should persist nulls for empty-string nullable fields'
);

-- Should raise an error when the alliance does not exist
select throws_ok(
    format(
        $$select update_alliance(
        null::uuid,
        %L::uuid,
        '{
            "description": "Some description",
            "display_name": "Some Alliance",
            "logo_url": "https://some.com/logo.png"
        }'::jsonb
    )$$,
        :'unknownAllianceID'
    ),
    'alliance not found',
    'Should raise an error when the alliance does not exist'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
