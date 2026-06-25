-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c0a0000-0000-0000-0000-000000000001'
\set groupCategoryID '0c0a0000-0000-0000-0000-000000000002'
\set groupID '0c0a0000-0000-0000-0000-000000000003'
\set groupInactiveID '0c0a0000-0000-0000-0000-000000000004'
\set regionID '0c0a0000-0000-0000-0000-000000000005'
\set sponsor1ID '0c0a0000-0000-0000-0000-000000000006'
\set sponsor2ID '0c0a0000-0000-0000-0000-000000000007'
\set unknownCommunityID '0c0a0000-0000-0000-0000-000000000008'
\set unknownGroupID '0c0a0000-0000-0000-0000-000000000009'
\set user1ID '0c0a0000-0000-0000-0000-00000000000a'
\set user2ID '0c0a0000-0000-0000-0000-00000000000b'
\set user3ID '0c0a0000-0000-0000-0000-00000000000c'
\set user4ID '0c0a0000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url,

    ad_banner_link_url,
    ad_banner_url,
    og_image_url
) values (
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png',

    'https://example.com/ad-banner-link',
    'https://example.com/ad-banner.png',
    'https://example.com/community-og.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Region
insert into region (region_id, community_id, name)
values (:'regionID', :'communityID', 'North America');

-- User
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    bio,
    bluesky_url,
    company,
    facebook_url,
    github_url,
    linkedin_url,
    name,
    photo_url,
    provider,
    title,
    twitter_url,
    website_url
) values (
    :'user1ID',
    'test_hash',
    'alice@seattle.cloudnative.org',
    false,
    'alice-organizer',
    'Community meetup organizer',
    'https://bsky.app/profile/alice',
    'Cloud Co',
    'https://facebook.com/alice',
    'https://github.com/alice',
    'https://linkedin.com/in/alice',
    'Alice Johnson',
    'https://example.com/alice.png',
    jsonb_build_object(
        'linuxfoundation', jsonb_build_object(
            'issuer', 'https://issuer.example.com',
            'subject', 'auth0|alice',
            'username', 'alice-lf'
        )
    ),
    'Manager',
    'https://twitter.com/alice',
    'https://alice.com'
), (
    :'user2ID',
    'test_hash',
    'bob@seattle.cloudnative.org',
    false,
    'bob-organizer',
    'Cloud native program lead',
    null,
    'StartUp',
    null,
    'https://github.com/bob',
    'https://linkedin.com/in/bob',
    'Bob Wilson',
    'https://example.com/bob.png',
    null,
    'Engineer',
    null,
    'https://bob.com'
), (
    :'user3ID',
    'test_hash',
    'charlie@seattle.cloudnative.org',
    false,
    'charlie-member',
    null,
    null,
    null,
    null,
    null,
    null,
    'Charlie Brown',
    null,
    null,
    null,
    null,
    null
), (
    :'user4ID',
    'test_hash',
    'diana@seattle.cloudnative.org',
    false,
    'diana-member',
    null,
    null,
    null,
    null,
    null,
    null,
    'Diana Prince',
    null,
    null,
    null,
    null,
    null
);

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    region_id,
    active,
    city,
    state,
    country_code,
    country_name,
    description,
    description_short,
    logo_url,
    banner_url,
    location,
    tags,
    website_url,
    bluesky_url,
    facebook_url,
    twitter_url,
    linkedin_url,
    github_url,
    instagram_url,
    youtube_url,
    slack_url,
    flickr_url,
    wechat_url,
    photos_urls,
    og_image_url,
    extra_links,
    payment_recipient,
    created_at
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Seattle Kubernetes Meetup',
    'abc1234',

    :'regionID',
    true,
    'New York',
    'NY',
    'US',
    'United States',
    'A technology group focused on Kubernetes and cloud native technologies',
    'A brief overview of the Seattle Kubernetes group',
    'https://example.com/group-logo.png',
    'https://example.com/group-banner.png',
    ST_SetSRID(ST_MakePoint(-74.006, 40.7128), 4326),
    array['kubernetes', 'cloud-native', 'containers'],
    'https://seattle.kubernetes.com',
    'https://bsky.app/profile/seattlek8s',
    'https://facebook.com/seattlek8s',
    'https://twitter.com/seattlek8s',
    'https://linkedin.com/company/seattlek8s',
    'https://github.com/seattlek8s',
    'https://instagram.com/seattlek8s',
    'https://youtube.com/@seattlek8s',
    'https://seattlek8s.slack.com',
    'https://flickr.com/seattlek8s',
    'https://wechat.com/seattlek8s',
    array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'https://example.com/group-og.png',
    jsonb_build_array(
        jsonb_build_object('name', 'Discord', 'url', 'https://discord.gg/seattlek8s'),
        jsonb_build_object('name', 'Forum', 'url', 'https://forum.seattlek8s.com')
    ),
    jsonb_build_object('provider', 'stripe', 'recipient_id', 'acct_test_group'),
    '2024-01-15 10:00:00+00'
);

-- Group Sponsor
insert into group_sponsor (
    group_sponsor_id,
    group_id,
    logo_url,
    name,
    website_url
) values
    (
        :'sponsor1ID',
        :'groupID',
        'https://example.com/logos/devops-tools.png',
        'DevOps Tools Inc',
        'https://devopstools.example.com'
    ),
    (
        :'sponsor2ID',
        :'groupID',
        'https://example.com/logos/kube-corp.png',
        'Kube Corp',
        null
    );

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order")
values
    (:'groupID', :'user1ID', 'admin', true, 1),
    (:'groupID', :'user2ID', 'admin', true, 2);

-- Group Member
insert into group_member (group_id, user_id)
values
    (:'groupID', :'user1ID'),
    (:'groupID', :'user2ID'),
    (:'groupID', :'user3ID'),
    (:'groupID', :'user4ID');

-- Group (inactive)
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active,
    created_at
) values (
    :'groupInactiveID',
    :'communityID',
    :'groupCategoryID',
    'Inactive DevOps Group',
    'xyz9876',

    false,
    '2024-02-15 10:00:00+00'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return complete group JSON
select is(
    get_group_full(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb,
    '{
        "active": true,
        "category": {
            "group_category_id": "0c0a0000-0000-0000-0000-000000000002",
            "name": "Technology",
            "normalized_name": "technology"
        },
        "created_at": 1705312800,
        "group_id": "0c0a0000-0000-0000-0000-000000000003",
        "members_count": 4,
        "name": "Seattle Kubernetes Meetup",
        "slug": "abc1234",
        "banner_url": "https://example.com/group-banner.png",
        "city": "New York",
        "country_code": "US",
        "country_name": "United States",
        "description": "A technology group focused on Kubernetes and cloud native technologies",
        "description_short": "A brief overview of the Seattle Kubernetes group",
        "extra_links": [{"name": "Discord", "url": "https://discord.gg/seattlek8s"}, {"name": "Forum", "url": "https://forum.seattlek8s.com"}],
        "bluesky_url": "https://bsky.app/profile/seattlek8s",
        "facebook_url": "https://facebook.com/seattlek8s",
        "flickr_url": "https://flickr.com/seattlek8s",
        "github_url": "https://github.com/seattlek8s",
        "instagram_url": "https://instagram.com/seattlek8s",
        "latitude": 40.7128,
        "linkedin_url": "https://linkedin.com/company/seattlek8s",
        "logo_url": "https://example.com/group-logo.png",
        "longitude": -74.006,
        "og_image_url": "https://example.com/group-og.png",
        "payment_recipient": {
            "provider": "stripe",
            "recipient_id": "acct_test_group"
        },
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "region": {
            "region_id": "0c0a0000-0000-0000-0000-000000000005",
            "name": "North America",
            "normalized_name": "north-america"
        },
        "slack_url": "https://seattlek8s.slack.com",
        "state": "NY",
        "tags": ["kubernetes", "cloud-native", "containers"],
        "twitter_url": "https://twitter.com/seattlek8s",
        "wechat_url": "https://wechat.com/seattlek8s",
        "website_url": "https://seattle.kubernetes.com",
        "youtube_url": "https://youtube.com/@seattlek8s",
        "community": {
            "banner_mobile_url": "https://example.com/banner_mobile.png",
            "banner_url": "https://example.com/banner.png",
            "community_id": "0c0a0000-0000-0000-0000-000000000001",
            "display_name": "Cloud Native Seattle",
            "logo_url": "https://example.com/logo.png",
            "name": "cloud-native-seattle",
            "ad_banner_link_url": "https://example.com/ad-banner-link",
            "ad_banner_url": "https://example.com/ad-banner.png",
            "og_image_url": "https://example.com/community-og.png"
        },
        "organizers": [
            {
                "user_id": "0c0a0000-0000-0000-0000-00000000000a",
                "username": "alice-organizer",
                "bio": "Community meetup organizer",
                "bluesky_url": "https://bsky.app/profile/alice",
                "name": "Alice Johnson",
                "company": "Cloud Co",
                "facebook_url": "https://facebook.com/alice",
                "github_url": "https://github.com/alice",
                "linkedin_url": "https://linkedin.com/in/alice",
                "photo_url": "https://example.com/alice.png",
                "provider": {
                    "linuxfoundation": {
                        "username": "alice-lf"
                    }
                },
                "title": "Manager",
                "twitter_url": "https://twitter.com/alice",
                "website_url": "https://alice.com"
            },
            {
                "user_id": "0c0a0000-0000-0000-0000-00000000000b",
                "username": "bob-organizer",
                "bio": "Cloud native program lead",
                "name": "Bob Wilson",
                "company": "StartUp",
                "github_url": "https://github.com/bob",
                "linkedin_url": "https://linkedin.com/in/bob",
                "photo_url": "https://example.com/bob.png",
                "title": "Engineer",
                "website_url": "https://bob.com"
            }
        ],
        "sponsors": [
            {
                "featured": true,
                "group_sponsor_id": "0c0a0000-0000-0000-0000-000000000006",
                "logo_url": "https://example.com/logos/devops-tools.png",
                "name": "DevOps Tools Inc",
                "website_url": "https://devopstools.example.com"
            },
            {
                "featured": true,
                "group_sponsor_id": "0c0a0000-0000-0000-0000-000000000007",
                "logo_url": "https://example.com/logos/kube-corp.png",
                "name": "Kube Corp"
            }
        ]
    }'::jsonb,
    'Should return complete group data with organizers and member count as JSON'
);

-- Should use community logo when group has no logo
update "group" set logo_url = null where group_id = :'groupID';
select is(
    (get_group_full(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb)->>'logo_url',
    'https://example.com/logo.png',
    'Should use community logo when group has no logo'
);
update "group" set logo_url = 'https://example.com/group-logo.png' where group_id = :'groupID';

-- Should include pretty slug when available
update "group" set slug_pretty = 'seattle-kubernetes' where group_id = :'groupID';
select is(
    (get_group_full(
        :'communityID'::uuid,
        :'groupID'::uuid
    )::jsonb)->>'slug_pretty',
    'seattle-kubernetes',
    'Should include pretty slug when available'
);
update "group" set slug_pretty = null where group_id = :'groupID';

-- Should return null for non-existent group
select ok(
    get_group_full(
        :'communityID'::uuid,
        :'unknownGroupID'::uuid
    ) is null,
    'Should return null for non-existent group ID'
);

-- Should return null when community does not match group
select ok(
    get_group_full(
        :'unknownCommunityID'::uuid,
        :'groupID'::uuid
    ) is null,
    'Should return null when community does not match group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
