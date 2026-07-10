-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================
\set category1ID '3a390000-0000-0000-0000-000000000001'
\set category2ID '3a390000-0000-0000-0000-000000000002'
\set community1ID '3a390000-0000-0000-0000-000000000003'
\set event1ID '3a390000-0000-0000-0000-000000000004'
\set event4ID '3a390000-0000-0000-0000-000000000005'
\set event10ID '3a390000-0000-0000-0000-000000000006'
\set event11ID '3a390000-0000-0000-0000-000000000007'
\set event12ID '3a390000-0000-0000-0000-000000000008'
\set event18ID '3a390000-0000-0000-0000-000000000009'
\set eventWaitlistWindowID '3a390000-0000-0000-0000-000000000021'
\set group1ID '3a390000-0000-0000-0000-000000000010'
\set label1ID '3a390000-0000-0000-0000-000000000011'
\set label2ID '3a390000-0000-0000-0000-000000000012'
\set label3ID '3a390000-0000-0000-0000-000000000013'
\set label4ID '3a390000-0000-0000-0000-000000000014'
\set sponsorNewID '3a390000-0000-0000-0000-000000000015'
\set sponsorOrigID '3a390000-0000-0000-0000-000000000016'
\set user1ID '3a390000-0000-0000-0000-000000000009'
\set user2ID '3a390000-0000-0000-0000-000000000017'
\set user3ID '3a390000-0000-0000-0000-000000000018'
\set waitlistUserID '3a390000-0000-0000-0000-000000000022'

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
    logo_url
) values (
    :'community1ID',
    'test-community',
    'Test Community',
    'A test community for testing purposes',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Users
insert into "user" (user_id, auth_hash, email, username, name) values
    (:'user1ID', 'hash1', 'host1@example.com', 'host1', 'Host One'),
    (:'user2ID', 'hash2', 'host2@example.com', 'host2', 'Host Two'),
    (:'user3ID', 'hash3', 'speaker1@example.com', 'speaker1', 'Speaker One'),
    (:'waitlistUserID', 'hash4', 'waitlist@example.com', 'waitlist', 'Waitlist User');

-- Event Category
insert into event_category (event_category_id, name, community_id)
values
    (:'category1ID', 'Conference', :'community1ID'),
    (:'category2ID', 'Workshop', :'community1ID');

-- Group Category
insert into group_category (group_category_id, name, community_id)
values ('3a390000-0000-0000-0000-000000000006', 'Technology', :'community1ID');

-- Group
insert into "group" (
    group_id,
    community_id,
    name,
    slug,
    description,
    group_category_id
) values (
    :'group1ID',
    :'community1ID',
    'Test Group',
    'abc1234',
    'A test group',
    '3a390000-0000-0000-0000-000000000006'
);

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsorOrigID', :'group1ID', 'Original Sponsor', 'https://example.com/sponsor.png', null),
    (
        :'sponsorNewID',
        :'group1ID',
        'NewSponsor Inc',
        'https://example.com/newsponsor.png',
        'https://newsponsor.com'
    );

-- Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id
) values (
    :'event1ID',
    :'group1ID',
    'Original Event',
    'def5678',
    'Original description',
    'America/New_York',
    :'category1ID',
    'in-person'
);

-- Add initial host and sponsor to the event
insert into event_host (event_id, user_id) values (:'event1ID', :'user1ID');

-- Initial speaker synchronized by the event update
insert into event_speaker (event_id, user_id, featured) values (:'event1ID', :'user1ID', true);

-- Initial sponsor synchronized by the event update
insert into event_sponsor (event_id, group_sponsor_id, level)
values (:'event1ID', :'sponsorOrigID', 'Bronze');

-- Canceled Event
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,

    canceled
) values (
    :'event4ID',
    :'group1ID',
    'Canceled Event',
    'pqr4jkl',
    'This event was canceled',
    'America/New_York',
    :'category1ID',
    'in-person',

    true
);

-- Published event used for reminder evaluation checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published
) values (
    :'event10ID',
    :'group1ID',
    'Reminder Event',
    'yz12abc',
    'Published event for reminder evaluation checks',
    'UTC',
    :'category1ID',
    'virtual',
    current_timestamp + interval '2 days',
    current_timestamp + interval '2 days 2 hours',
    true
);

-- Published soon-starting event used for reminder regression checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    published
) values (
    :'event11ID',
    :'group1ID',
    'Reminder Event Soon',
    'lmn45op',
    'Published soon event for reminder regression checks',
    'UTC',
    :'category1ID',
    'virtual',
    current_timestamp + interval '10 hours',
    current_timestamp + interval '12 hours',
    true
);

-- Event used for CFS labels update checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    cfs_description,
    cfs_enabled,
    cfs_ends_at,
    cfs_starts_at,
    starts_at,
    ends_at
) values (
    :'event12ID',
    :'group1ID',
    'Event With Labels',
    'opq67rs',
    'Event seeded for CFS labels update tests',
    'UTC',
    :'category1ID',
    'virtual',
    'Initial CFS description',
    true,
    '2030-01-05 00:00:00+00',
    '2029-12-20 00:00:00+00',
    '2030-01-15 10:00:00+00',
    '2030-01-15 12:00:00+00'
);

-- Event used for CFS label upsert checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    cfs_description,
    cfs_enabled,
    cfs_ends_at,
    cfs_starts_at,
    starts_at,
    ends_at
) values (
    :'event18ID',
    :'group1ID',
    'Event With Labels For Upsert',
    'upsert-labels',
    'Event seeded for CFS labels upsert tests',
    'UTC',
    :'category1ID',
    'virtual',
    'Initial CFS description',
    true,
    '2030-01-05 00:00:00+00',
    '2029-12-20 00:00:00+00',
    '2030-01-15 10:00:00+00',
    '2030-01-15 12:00:00+00'
);

-- Live event used for update-driven waitlist promotion checks
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    starts_at,
    ends_at,
    registration_starts_at,
    published,
    capacity,
    waitlist_enabled
) values (
    :'eventWaitlistWindowID',
    :'group1ID',
    'Open Only Waitlist Event',
    'open-only-waitlist-event',
    'Event seeded for registration window waitlist update tests',
    'UTC',
    :'category1ID',
    'in-person',
    date_trunc('second', current_timestamp - interval '1 hour'),
    date_trunc('second', current_timestamp + interval '1 hour'),
    date_trunc('second', current_timestamp - interval '2 hours'),
    true,
    1,
    true
);

-- CFS labels seeded for update and upsert checks
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label1ID', :'event12ID', '#CCFBF1', 'track / backend'),
    (:'label2ID', :'event12ID', '#FEE2E2', 'track / frontend');

-- Existing labels owned by a different event
insert into event_cfs_label (event_cfs_label_id, event_id, color, name) values
    (:'label3ID', :'event18ID', '#CCFBF1', 'track / backend'),
    (:'label4ID', :'event18ID', '#FEE2E2', 'track / frontend');

-- Attendee used by reminder evaluation checks
insert into event_attendee (event_id, user_id)
values (:'event10ID', :'user1ID');

-- Occupied seat and waitlist entry used by update-driven promotion checks
insert into event_attendee (event_id, user_id)
values (:'eventWaitlistWindowID', :'user2ID');

-- Waitlisted user eligible for promotion after the event update
insert into event_waitlist (event_id, user_id, created_at)
values (:'eventWaitlistWindowID', :'waitlistUserID', current_timestamp - interval '30 minutes');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should update basic fields and clear hosts/sponsors/sessions when not provided
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Updated Event Name",
            "description": "Updated description",
            "timezone": "America/Los_Angeles",
            "category_id": "3a390000-0000-0000-0000-000000000002",
            "kind_id": "virtual",
            "capacity": 100,
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "meeting_provider_id": "zoom",
            "meeting_requested": true
        }'::jsonb
    )$$,
    'Should execute basic update and clear omitted hosts, sponsors, and sessions'
);
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'cfs_labels'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Workshop",
        "description": "Updated description",
        "hosts": [],
        "kind": "virtual",
        "logo_url": "https://example.com/logo.png",
        "name": "Updated Event Name",
        "published": false,
        "slug": "def5678",
        "speakers": [],
        "sponsors": [],
        "test_event": false,
        "timezone": "America/Los_Angeles",

        "attendee_approval_required": false,
        "capacity": 100,
        "remaining_capacity": 100,
        "ends_at": 1896220800,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "meeting_in_sync": false,
        "meeting_provider": "zoom",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_requested": true,
        "registration_questions": [],
        "registration_questions_locked": false,
        "sessions": {},
        "starts_at": 1896213600,
        "waitlist_count": 0,
        "waitlist_enabled": false
    }'::jsonb,
    'Should persist basic update and clear omitted hosts, sponsors, and sessions'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
    $$,
    $$
        values (
            'event_updated',
            null::uuid,
            null::text,
            '3a390000-0000-0000-0000-000000000003'::uuid,
            '3a390000-0000-0000-0000-000000000010'::uuid,
            '3a390000-0000-0000-0000-000000000004'::uuid,
            'event',
            '3a390000-0000-0000-0000-000000000004'::uuid
        )
    $$,
    'Should create the expected audit row'
);

-- Should initialize meeting flags for requested event without sessions
select is(
    (
        select jsonb_build_object(
            'meeting_requested', meeting_requested,
            'meeting_in_sync', meeting_in_sync
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "meeting_requested": true,
        "meeting_in_sync": false
    }'::jsonb,
    'Meeting flags are initialized for requested event without sessions'
);

-- Should update all fields (excluding sessions) with full payload
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{
            "name": "Fully Updated Event",
            "description": "Fully updated description",
            "timezone": "Asia/Tokyo",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "hybrid",
            "meeting_requested": false,
            "banner_url": "https://example.com/new-banner.jpg",
            "capacity": 200,
            "description_short": "Updated short description",
            "starts_at": "2030-02-01T14:00:00",
            "ends_at": "2030-02-01T16:00:00",
            "logo_url": "https://example.com/new-logo.png",
            "luma_url": "https://luma.com/new-event",
            "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
            "meeting_join_instructions": "Use the event ticket name when joining.",
            "meeting_join_url": "https://youtube.com/new-live",
            "meeting_recording_url": "https://youtube.com/new-recording",
            "meetup_url": "https://meetup.com/new-event",
            "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
            "registration_required": false,
            "tags": ["updated", "event", "tags"],
            "test_event": true,
            "venue_address": "456 New St",
            "venue_city": "Tokyo",
            "venue_country_code": "JP",
            "venue_country_name": "Japan",
            "venue_name": "New Venue",
            "venue_state": "TK",
            "venue_zip_code": "100-0001",
            "hosts": ["3a390000-0000-0000-0000-000000000017", "3a390000-0000-0000-0000-000000000018"],
            "speakers": [
                {"user_id": "3a390000-0000-0000-0000-000000000017", "featured": true},
                {"user_id": "3a390000-0000-0000-0000-000000000018", "featured": false}
            ],
            "sponsors": [{"group_sponsor_id": "3a390000-0000-0000-0000-000000000015", "level": "Platinum"}],
            "sessions": [
                {
                    "name": "Updated Session",
                    "description": "This is an updated session",
                    "starts_at": "2030-02-01T14:30:00",
                    "ends_at": "2030-02-01T15:30:00",
                    "kind": "virtual",
                    "meeting_hosts": ["session-althost@example.com"],
                    "meeting_provider_id": "zoom",
                    "meeting_requested": true,
                    "speakers": [{"user_id": "3a390000-0000-0000-0000-000000000017", "featured": true}]
                }
            ]
        }'::jsonb
    )$$,
    'Should update all fields (excluding sessions) with full payload'
);

-- Check event fields except sessions
select is(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb - 'community' - 'created_at' - 'event_id' - 'organizers' - 'group' - 'legacy_hosts' - 'legacy_speakers' - 'sessions' - 'cfs_labels'
    )),
    '{
        "attendee_count": 0,
        "canceled": false,
        "category_name": "Conference",
        "description": "Fully updated description",
        "hosts": [
            {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2"},
            {"name": "Speaker One", "user_id": "3a390000-0000-0000-0000-000000000018", "username": "speaker1"}
        ],
        "speakers": [
            {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2", "featured": true},
            {"name": "Speaker One", "user_id": "3a390000-0000-0000-0000-000000000018", "username": "speaker1", "featured": false}
        ],
        "kind": "hybrid",
        "meeting_hosts": ["althost1@example.com", "althost2@example.com"],
        "meeting_in_sync": false,
        "meeting_requested": false,
        "name": "Fully Updated Event",
        "published": false,
        "slug": "def5678",
        "timezone": "Asia/Tokyo",
        "test_event": true,
        "attendee_approval_required": false,
        "banner_url": "https://example.com/new-banner.jpg",
        "capacity": 200,
        "remaining_capacity": 200,
        "description_short": "Updated short description",
        "starts_at": 1896152400,
        "ends_at": 1896159600,
        "logo_url": "https://example.com/new-logo.png",
        "luma_url": "https://luma.com/new-event",
        "meeting_join_instructions": "Use the event ticket name when joining.",
        "meeting_join_url": "https://youtube.com/new-live",
        "meeting_recording_published": false,
        "meeting_recording_requested": true,
        "meeting_recording_url": "https://youtube.com/new-recording",
        "meetup_url": "https://meetup.com/new-event",
        "photos_urls": ["https://example.com/new-photo1.jpg", "https://example.com/new-photo2.jpg"],
        "registration_questions": [],
        "registration_questions_locked": false,
        "registration_required": false,
        "event_reminder_enabled": true,
        "has_registration_questions": false,
        "has_related_events": false,
        "has_ticket_purchases": false,
        "tags": ["updated", "event", "tags"],
        "venue_address": "456 New St",
        "venue_city": "Tokyo",
        "venue_country_code": "JP",
        "venue_country_name": "Japan",
        "venue_name": "New Venue",
        "venue_state": "TK",
        "venue_zip_code": "100-0001",
        "waitlist_count": 0,
        "waitlist_enabled": false,
        "sponsors": [
            {"group_sponsor_id": "3a390000-0000-0000-0000-000000000015", "level": "Platinum", "logo_url": "https://example.com/newsponsor.png", "name": "NewSponsor Inc", "website_url": "https://newsponsor.com"}
        ]
    }'::jsonb,
    'Should update all fields (excluding sessions)'
);

-- Should contain expected session rows (ignoring session_id)
select ok(
    (select (
        get_event_full(
            :'community1ID'::uuid,
            :'group1ID'::uuid,
            :'event1ID'::uuid
        )::jsonb->'sessions'->'2030-02-01'
    ) @>
        '[
            {
                "name": "Updated Session",
                "description": "This is an updated session",
                "starts_at": 1896154200,
                "ends_at": 1896157800,
                "kind": "virtual",
                "meeting_hosts": ["session-althost@example.com"],
                "meeting_provider": "zoom",
                "meeting_requested": true,
                "speakers": [
                    {"name": "Host Two", "user_id": "3a390000-0000-0000-0000-000000000017", "username": "host2", "featured": true}
                ]
            }
        ]'::jsonb
    ),
    'Sessions contain expected rows (ignoring session_id)'
);

-- Should set meeting_in_sync=false when meeting disabled to trigger deletion
select is(
    (
        select jsonb_build_object(
            'event', jsonb_build_object(
                'meeting_requested', meeting_requested,
                'meeting_in_sync', meeting_in_sync
            ),
            'session', (
                select jsonb_build_object(
                    'meeting_requested', meeting_requested,
                    'meeting_in_sync', meeting_in_sync
                )
                from session
                where event_id = :'event1ID'::uuid
            )
        )
        from event
        where event_id = :'event1ID'::uuid
    ),
    '{
        "event": {
            "meeting_requested": false,
            "meeting_in_sync": false
        },
        "session": {
            "meeting_requested": true,
            "meeting_in_sync": false
        }
    }'::jsonb,
    'Should set meeting_in_sync=false when meeting disabled to trigger deletion'
);

-- Should clear CFS labels when payload omits cfs_labels
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000008'::uuid,
        '{
            "name": "Event With Labels",
            "description": "Event seeded for CFS labels update tests",
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "cfs_description": "Initial CFS description",
            "cfs_enabled": true,
            "cfs_starts_at": "2029-12-20T00:00:00",
            "cfs_ends_at": "2030-01-05T00:00:00",
            "starts_at": "2030-01-15T10:00:00",
            "ends_at": "2030-01-15T12:00:00"
        }'::jsonb
    )$$,
    'Should clear CFS labels when payload omits cfs_labels'
);

-- Should delete all CFS labels when payload omits cfs_labels
select is(
    (select count(*) from event_cfs_label where event_id = :'event12ID'::uuid),
    0::bigint,
    'Should delete all CFS labels when payload omits cfs_labels'
);

-- Should update CFS labels for an event
select lives_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000009'::uuid,
        '{
            "name": "Event With Labels For Upsert",
            "description": "Event seeded for CFS labels upsert tests",
            "timezone": "UTC",
            "category_id": "3a390000-0000-0000-0000-000000000001",
            "kind_id": "virtual",
            "cfs_description": "Updated CFS description",
            "cfs_enabled": true,
            "cfs_starts_at": "2029-12-22T00:00:00",
            "cfs_ends_at": "2030-01-07T00:00:00",
            "starts_at": "2030-01-15T10:00:00",
            "ends_at": "2030-01-15T12:00:00",
            "cfs_labels": [
                {
                    "event_cfs_label_id": "3a390000-0000-0000-0000-000000000013",
                    "name": "track / ai + ml",
                    "color": "#DBEAFE"
                },
                {
                    "name": "track / web",
                    "color": "#FEE2E2"
                }
            ]
        }'::jsonb
    )$$,
    'Should update CFS labels for an event'
);

-- Should upsert and prune CFS labels in event_cfs_label
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'color', color,
                'name', name
            )
            order by name
        )
        from event_cfs_label
        where event_id = :'event18ID'::uuid
    ),
    '[
        {"color": "#DBEAFE", "name": "track / ai + ml"},
        {"color": "#FEE2E2", "name": "track / web"}
    ]'::jsonb,
    'Should upsert and prune CFS labels in event_cfs_label'
);

-- Should return updated CFS labels in event payload
select is(
    (
        select jsonb_agg(
            jsonb_build_object(
                'color', label->>'color',
                'name', label->>'name'
            )
            order by label->>'name'
        )
        from jsonb_array_elements(
            get_event_full(
                :'community1ID'::uuid,
                :'group1ID'::uuid,
                :'event18ID'::uuid
            )::jsonb->'cfs_labels'
        ) as label
    ),
    '[
        {"color": "#DBEAFE", "name": "track / ai + ml"},
        {"color": "#FEE2E2", "name": "track / web"}
    ]'::jsonb,
    'Should return updated CFS labels in event payload'
);

-- Should throw error when group_id does not match
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000019'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Won''t Work", "description": "This should fail", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- Should throw error when updating cancelled event
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000005'::uuid,
        '{"name": "Try to Update Canceled", "description": "This should fail", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person"}'::jsonb
    )$$,
    'event not found or inactive',
    'Should throw error when event is canceled'
);

-- Should throw error for invalid host user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Event with Invalid Host", "description": "Test", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person", "hosts": ["3a390000-0000-0000-0000-000000000020"]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when host user_id does not exist'
);

-- Should throw error for invalid speaker user_id (FK violation)
select throws_ok(
    $$select update_event(
        null::uuid,
        '3a390000-0000-0000-0000-000000000010'::uuid,
        '3a390000-0000-0000-0000-000000000004'::uuid,
        '{"name": "Event with Invalid Speaker", "description": "Test", "timezone": "UTC", "category_id": "3a390000-0000-0000-0000-000000000001", "kind_id": "in-person", "speakers": [{"user_id": "3a390000-0000-0000-0000-000000000020", "featured": false}]}'::jsonb
    )$$,
    '23503',
    null,
    'Should throw error when speaker user_id does not exist'
);

-- Should evaluate reminder immediately when published event starts within 24 hours
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Reminder Event Updated',
                'description', 'Reminder evaluation check',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'virtual',
                'event_reminder_enabled', true,
                'starts_at', to_char(current_timestamp + interval '12 hours', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char(current_timestamp + interval '14 hours', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event10ID', :'category1ID'
    ),
    'Should evaluate reminder immediately when published event starts within 24 hours'
);

-- Should mark reminder as evaluated for the updated start date
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event10ID'),
    (select starts_at from event where event_id = :'event10ID'),
    'Should mark reminder as evaluated for the updated start date'
);

-- Should not evaluate reminder when starts_at remains unchanged inside 24 hours
select lives_ok(
    format(
        $$select update_event(
            null::uuid,
            '%s'::uuid,
            '%s'::uuid,
            jsonb_build_object(
                'name', 'Reminder Event Soon Updated',
                'description', 'Reminder regression check',
                'timezone', 'UTC',
                'category_id', '%s',
                'kind_id', 'virtual',
                'event_reminder_enabled', true,
                'starts_at', to_char((select starts_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS'),
                'ends_at', to_char((select ends_at from event where event_id = '%s'::uuid) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
            )
        )$$,
        :'group1ID', :'event11ID', :'category1ID', :'event11ID', :'event11ID'
    ),
    'Should not evaluate reminder when starts_at remains unchanged inside 24 hours'
);

-- Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours
select is(
    (select event_reminder_evaluated_for_starts_at from event where event_id = :'event11ID'),
    null::timestamptz,
    'Should keep reminder unevaluated when starts_at remains unchanged inside 24 hours'
);

-- Should not promote waitlist entries after an open-only registration window reaches the event start
select is(
    update_event(
        null::uuid,
        :'group1ID'::uuid,
        :'eventWaitlistWindowID'::uuid,
        jsonb_build_object(
            'name', 'Open Only Waitlist Event Updated',
            'description', 'Event seeded for registration window waitlist update tests',
            'timezone', 'UTC',
            'category_id', :'category1ID',
            'kind_id', 'in-person',
            'capacity', 2,
            'starts_at', to_char(
                (
                    select starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'ends_at', to_char(
                (
                    select ends_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'registration_starts_at', to_char(
                (
                    select registration_starts_at
                    from event
                    where event_id = :'eventWaitlistWindowID'::uuid
                ) at time zone 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS'
            ),
            'waitlist_enabled', true
        )
    )::jsonb,
    '[]'::jsonb,
    'Should not promote waitlist entries after an open-only registration window reaches the event start'
);

select is(
    (
        select jsonb_agg(user_id order by created_at asc, user_id asc)
        from event_waitlist
        where event_id = :'eventWaitlistWindowID'::uuid
    ),
    format('["%s"]', :'waitlistUserID')::jsonb,
    'Should keep waitlist entries queued after an open-only registration window reaches the event start'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
