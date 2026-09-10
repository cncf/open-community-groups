-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '6a010000-0000-0000-0000-000000000001'
\set groupCategoryID '6a010000-0000-0000-0000-000000000002'
\set groupDeletedID '6a010000-0000-0000-0000-00000000000a'
\set groupID '6a010000-0000-0000-0000-000000000003'
\set groupPrettySlugID '6a010000-0000-0000-0000-00000000000b'
\set memberID '6a010000-0000-0000-0000-000000000004'
\set organizer1ID '6a010000-0000-0000-0000-000000000005'
\set organizer2ID '6a010000-0000-0000-0000-000000000006'
\set regionID '6a010000-0000-0000-0000-000000000007'
\set sponsor1ID '6a010000-0000-0000-0000-000000000008'
\set sponsor2ID '6a010000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community returned in group details
select fx_community(:'communityID', jsonb_build_object(
    'banner_mobile_url', 'https://example.com/banner_mobile.png',
    'banner_url', 'https://example.com/banner.png',
    'display_name', 'Cloud Native Seattle Group Full By Slug',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-group-full-by-slug',
    'og_image_url', 'https://example.com/community-og.png'
));

-- Group category returned in group details
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Technology'));

-- Region
insert into region (region_id, name, community_id)
values (:'regionID', 'North America', :'communityID');

-- Organizers and member returned in group details
select fx_user(:'organizer1ID', jsonb_build_object(
    'bio', 'Group founder and speaker',
    'company', 'Tech Corp',
    'name', 'John Doe',
    'photo_url', 'https://example.com/john.png',
    'title', 'CTO',
    'username', 'organizer1'
));
select fx_user(:'organizer2ID', jsonb_build_object(
    'bio', 'Community events coordinator',
    'company', 'Dev Inc',
    'name', 'Jane Smith',
    'photo_url', 'https://example.com/jane.png',
    'title', 'Lead Dev',
    'username', 'organizer2'
));
select fx_user(:'memberID', jsonb_build_object(
    'company', 'StartUp',
    'photo_url', 'https://example.com/bob.png'
));

-- Group returned by full-detail slug lookup
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'banner_url', 'https://example.com/k8s-banner.png',
    'bluesky_url', 'https://bsky.app/profile/k8snyc',
    'city', 'New York',
    'country_code', 'US',
    'country_name', 'United States',
    'description', 'New York Kubernetes meetup group for cloud native enthusiasts',
    'facebook_url', 'https://facebook.com/k8snyc',
    'github_url', 'https://github.com/k8snyc',
    'linkedin_url', 'https://linkedin.com/company/k8snyc',
    'location', ST_GeogFromText('POINT(-74.0060 40.7128)'),
    'logo_url', 'https://example.com/k8s-logo.png',
    'name', 'Kubernetes NYC',
    'og_image_url', 'https://example.com/group-og.png',
    'region_id', :'regionID',
    'slug', 'abc1234',
    'state', 'NY',
    'tags', array['kubernetes', 'cloud-native', 'devops'],
    'twitter_url', 'https://twitter.com/k8snyc',
    'website_url', 'https://k8s-nyc.example.com'
));

-- Deleted group variant excluded from slug lookup
select fx_group(:'groupDeletedID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'active', false,
    'deleted', true,
    'slug', 'deleted-kubernetes-nyc'
));

-- Pretty slug variant resolved by alternate slug
select fx_group(:'groupPrettySlugID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'slug_pretty', 'kubernetes-nyc'
));

-- Group Member
insert into group_member (group_id, user_id, created_at)
values
    (:'groupID', :'organizer1ID', '2024-01-01 00:00:00'),
    (:'groupID', :'organizer2ID', '2024-01-01 00:00:00'),
    (:'groupID', :'memberID', '2024-01-01 00:00:00');

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order", created_at)
values
    (:'groupID', :'organizer1ID', 'admin', true, 1, '2024-01-01 00:00:00'),
    (:'groupID', :'organizer2ID', 'admin', true, 2, '2024-01-01 00:00:00');

-- Group Sponsors
insert into group_sponsor (
    group_sponsor_id,
    featured,
    group_id,
    logo_url,
    name,
    website_url
) values
    (
        :'sponsor1ID',
        true,
        :'groupID',
        'https://example.com/featured-sponsor.png',
        'Featured Sponsor',
        'https://featured-sponsor.example.com'
    ),
    (
        :'sponsor2ID',
        false,
        :'groupID',
        'https://example.com/hidden-sponsor.png',
        'Hidden Sponsor',
        'https://hidden-sponsor.example.com'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct group data as JSON
select is(
    get_group_full_by_slug(:'communityID'::uuid, 'abc1234')::jsonb - '{created_at}'::text[],
    format(
        $json$
    {
        "active": true,
        "external_payments_enabled": false,
        "city": "New York",
        "name": "Kubernetes NYC",
        "slug": "abc1234",
        "tags": ["kubernetes", "cloud-native", "devops"],
        "state": "NY",
        "group_id": "%s",
        "latitude": 40.7128,
        "logo_url": "https://example.com/k8s-logo.png",
        "sponsors": [
            {
                "featured": true,
                "group_sponsor_id": "%s",
                "logo_url": "https://example.com/featured-sponsor.png",
                "name": "Featured Sponsor",
                "website_url": "https://featured-sponsor.example.com"
            },
            {
                "featured": false,
                "group_sponsor_id": "%s",
                "logo_url": "https://example.com/hidden-sponsor.png",
                "name": "Hidden Sponsor",
                "website_url": "https://hidden-sponsor.example.com"
            }
        ],
        "subgroups": [],
        "longitude": -74.006,
        "og_image_url": "https://example.com/group-og.png",
        "banner_url": "https://example.com/k8s-banner.png",
        "community": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "community_id": "%s",
            "display_name": "Cloud Native Seattle Group Full By Slug",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle-group-full-by-slug",
            "og_image_url": "https://example.com/community-og.png"
        },
        "github_url": "https://github.com/k8snyc",
        "organizers": [
            {
                "title": "CTO",
                "company": "Tech Corp",
                "user_id": "%s",
                "username": "organizer1",
                "bio": "Group founder and speaker",
                "name": "John Doe",
                "photo_url": "https://example.com/john.png"
            },
            {
                "title": "Lead Dev",
                "company": "Dev Inc",
                "user_id": "%s",
                "username": "organizer2",
                "bio": "Community events coordinator",
                "name": "Jane Smith",
                "photo_url": "https://example.com/jane.png"
            }
        ],
        "description": "New York Kubernetes meetup group for cloud native enthusiasts",
        "region": {
            "region_id": "%s",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "bluesky_url": "https://bsky.app/profile/k8snyc",
        "twitter_url": "https://twitter.com/k8snyc",
        "website_url": "https://k8s-nyc.example.com",
        "country_code": "US",
        "country_name": "United States",
        "facebook_url": "https://facebook.com/k8snyc",
        "linkedin_url": "https://linkedin.com/company/k8snyc",
        "category": {
            "group_category_id": "%s",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "members_count": 3
    }
        $json$,
        :'groupID',
        :'sponsor1ID',
        :'sponsor2ID',
        :'communityID',
        :'organizer1ID',
        :'organizer2ID',
        :'regionID',
        :'groupCategoryID'
    )::jsonb,
    'Should return correct group data as JSON'
);

-- Should return null with non-existing group slug
select ok(
    get_group_full_by_slug(:'communityID'::uuid, 'non-existing-group') is null,
    'Should return null with non-existing group slug'
);

-- Should resolve group by pretty slug
select is(
    get_group_full_by_slug(:'communityID'::uuid, 'kubernetes-nyc')::jsonb->>'group_id',
    :'groupPrettySlugID',
    'Should resolve group by pretty slug'
);

-- Should return null when the matching group is deleted
select ok(
    get_group_full_by_slug(:'communityID'::uuid, 'deleted-kubernetes-nyc') is null,
    'Should return null when the matching group is deleted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
