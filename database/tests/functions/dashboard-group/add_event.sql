-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '00000000-0000-0000-0000-000000000001'
\set groupID '00000000-0000-0000-0000-000000000002'
\set categoryID '00000000-0000-0000-0000-000000000011'
\set groupCategoryID '00000000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community (for testing event creation)
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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'seattle.cloudnative.org',
    'Cloud Native Seattle Community',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/logo.png',
    '{}'::jsonb
);

-- Event category (for event classification)
insert into event_category (event_category_id, name, slug, community_id)
values (:'categoryID', 'Conference', 'conference', :'communityID');

-- Group category (for group organization)
insert into group_category (group_category_id, name, community_id)
values (:'groupCategoryID', 'Technology', :'communityID');

-- Group (for hosting events)
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'groupID',
    :'communityID',
    'Kubernetes Study Group',
    'kubernetes-study-group',
    'A study group focused on Kubernetes best practices and implementation',
    :'groupCategoryID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- add_event function creates event with required fields only
select is(
    (select (get_event_full(
        add_event(
            :'groupID'::uuid,
            '{"name": "Kubernetes Fundamentals Workshop", "slug": "k8s-fundamentals-workshop", "description": "Learn the basics of Kubernetes deployment and management", "timezone": "America/New_York", "category_id": "00000000-0000-0000-0000-000000000011", "kind_id": "in-person"}'::jsonb
        )
    )::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Learn the basics of Kubernetes deployment and management",
        "kind": "in-person",
        "name": "Kubernetes Fundamentals Workshop",
        "published": false,
        "slug": "k8s-fundamentals-workshop",
        "timezone": "America/New_York",
        "timezone_abbr": "EDT"
    }'::jsonb,
    'add_event should create event with minimal required fields and return expected structure'
);

-- add_event function creates event with all fields
select is(
    (select (get_event_full(
        add_event(
            :'groupID'::uuid,
            '{
                "name": "CloudNativeCon Seattle 2025",
                "slug": "cloudnativecon-seattle-2025",
                "description": "Premier conference for cloud native technologies and community collaboration",
                "timezone": "America/Los_Angeles",
                "category_id": "00000000-0000-0000-0000-000000000011",
                "kind_id": "hybrid",
                "banner_url": "https://example.com/banner.jpg",
                "capacity": 100,
                "description_short": "Short description",
                "starts_at": "2025-01-01T10:00:00",
                "ends_at": "2025-01-01T12:00:00",
                "logo_url": "https://example.com/logo.png",
                "meetup_url": "https://meetup.com/event",
                "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
                "recording_url": "https://youtube.com/recording",
                "registration_required": true,
                "streaming_url": "https://youtube.com/live",
                "tags": ["technology", "conference", "networking"],
                "venue_address": "123 Main St",
                "venue_city": "San Francisco",
                "venue_name": "Tech Center",
                "venue_zip_code": "94105"
            }'::jsonb
        )
    )::jsonb - 'created_at' - 'event_id' - 'hosts' - 'organizers' - 'sessions' - 'group')),
    '{
        "canceled": false,
        "category_name": "Conference",
        "description": "Premier conference for cloud native technologies and community collaboration",
        "kind": "hybrid",
        "name": "CloudNativeCon Seattle 2025",
        "published": false,
        "slug": "cloudnativecon-seattle-2025",
        "timezone": "America/Los_Angeles",
        "timezone_abbr": "PDT",
        "banner_url": "https://example.com/banner.jpg",
        "capacity": 100,
        "description_short": "Short description",
        "starts_at": 1735754400,
        "ends_at": 1735761600,
        "logo_url": "https://example.com/logo.png",
        "meetup_url": "https://meetup.com/event",
        "photos_urls": ["https://example.com/photo1.jpg", "https://example.com/photo2.jpg"],
        "recording_url": "https://youtube.com/recording",
        "registration_required": true,
        "streaming_url": "https://youtube.com/live",
        "tags": ["technology", "conference", "networking"],
        "venue_address": "123 Main St",
        "venue_city": "San Francisco",
        "venue_name": "Tech Center",
        "venue_zip_code": "94105"
    }'::jsonb,
    'add_event should create event with all fields and return expected structure'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
