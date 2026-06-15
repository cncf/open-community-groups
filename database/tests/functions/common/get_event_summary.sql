-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCheckoutUserID '0c090000-0000-0000-0000-000000000001'
\set attendee1ID '0c090000-0000-0000-0000-000000000002'
\set attendee2ID '0c090000-0000-0000-0000-000000000003'
\set communityID '0c090000-0000-0000-0000-000000000004'
\set eventCategoryID '0c090000-0000-0000-0000-000000000005'
\set eventCommunityLogoFallbackID '0c090000-0000-0000-0000-000000000006'
\set eventGroupLogoFallbackID '0c090000-0000-0000-0000-000000000007'
\set eventID '0c090000-0000-0000-0000-000000000008'
\set eventPaidID '0c090000-0000-0000-0000-000000000009'
\set eventQuestionsID '0c090000-0000-0000-0000-00000000000a'
\set eventSeriesID '0c090000-0000-0000-0000-00000000000b'
\set expiredCheckoutUserID '0c090000-0000-0000-0000-00000000000c'
\set groupCategoryID '0c090000-0000-0000-0000-00000000000d'
\set groupID '0c090000-0000-0000-0000-00000000000e'
\set groupNoLogoID '0c090000-0000-0000-0000-00000000000f'
\set pendingInviteID '0c090000-0000-0000-0000-000000000010'
\set questionID '0c090000-0000-0000-0000-000000000011'
\set questionsSeatedUserID '0c090000-0000-0000-0000-000000000012'
\set questionsWaitlistUserID '0c090000-0000-0000-0000-000000000013'
\set ticketPriceWindowID '0c090000-0000-0000-0000-000000000014'
\set ticketTypeID '0c090000-0000-0000-0000-000000000015'
\set unknownCommunityID '0c090000-0000-0000-0000-000000000016'
\set unknownEventID '0c090000-0000-0000-0000-000000000017'
\set unknownGroupID '0c090000-0000-0000-0000-000000000018'
\set waitlistUserID '0c090000-0000-0000-0000-000000000019'

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
    :'communityID',
    'cloud-native-seattle',
    'Cloud Native Seattle',
    'A vibrant community for cloud native technologies and practices in Seattle',
    'https://example.com/banner_mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Tech Talks');

-- Attendees for remaining capacity verification
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,

    created_at
) values (
    :'attendee1ID',
    'attendee-hash',
    'attendee1@example.com',
    true,
    'attendee1',

    '2024-01-01 00:00:00+00'
), (
    :'attendee2ID',
    'attendee-hash',
    'attendee2@example.com',
    true,
    'attendee2',

    '2024-01-01 00:00:00+00'
), (
    :'waitlistUserID',
    'attendee-hash',
    'waitlist@example.com',
    true,
    'waitlist-user',

    '2024-01-01 00:00:00+00'
), (
    :'pendingInviteID',
    'attendee-hash',
    'pending@example.com',
    true,
    'pending-invite',

    '2024-01-01 00:00:00+00'
), (
    :'expiredCheckoutUserID',
    'registration-hash',
    'rq-expired-checkout@test.com',
    true,
    'rq-expired-checkout',

    '2024-01-01 00:00:00+00'
), (
    :'activeCheckoutUserID',
    'registration-hash',
    'rq-active-checkout@test.com',
    true,
    'rq-active-checkout',

    '2024-01-01 00:00:00+00'
), (
    :'questionsSeatedUserID',
    'registration-hash',
    'rq-seated@test.com',
    true,
    'rq-seated',

    '2024-01-01 00:00:00+00'
), (
    :'questionsWaitlistUserID',
    'registration-hash',
    'rq-waitlist@test.com',
    true,
    'rq-waitlist',

    '2024-01-01 00:00:00+00'
);

-- Group
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active,
    logo_url
) values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Seattle Kubernetes Meetup',
    'abc1234',

    true,
    'https://example.com/group-logo.png'
);

-- Group without logo
insert into "group" (
    group_id,
    community_id,
    group_category_id,
    name,
    slug,

    active
) values (
    :'groupNoLogoID',
    :'communityID',
    :'groupCategoryID',
    'Seattle Kubernetes Meetup No Logo',
    'abc5678',

    true
);

-- Event Series
insert into event_series (
    event_series_id,
    group_id,
    recurrence_additional_occurrences,
    recurrence_anchor_starts_at,
    recurrence_pattern,
    timezone,

    created_by
) values (
    :'eventSeriesID',
    :'groupID',
    1,
    '2024-06-15 09:00:00+00',
    'weekly',
    'America/New_York',

    :'attendee1ID'
);

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    description_short,
    event_kind_id,
    event_category_id,
    group_id,
    published,
    starts_at,
    ends_at,
    timezone,
    meeting_join_instructions,
    meeting_join_url,
    venue_address,
    venue_city,
    venue_country_code,
    venue_country_name,
    venue_name,
    venue_state,
    venue_zip_code,
    capacity,
    payment_currency_code,
    waitlist_enabled,
    location,
    logo_url,

    event_series_id
) values (
    :'eventID',
    'KubeCon Seattle 2024',
    'def5678',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'Annual Kubernetes conference short summary',
    'in-person',
    :'eventCategoryID',
    :'groupID',
    true,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    'Use your registration name when joining.',
    null,
    '123 Main St',
    'New York',
    'US',
    'United States',
    'Convention Center',
    'NY',
    '10001',
    5,
    null,
    true,
    ST_SetSRID(
        ST_MakePoint(-122.3321, 47.6062),
        4326
    ),  -- Seattle coordinates (different from group)
    'https://example.com/event-logo.png',

    :'eventSeriesID'
), (
    :'eventGroupLogoFallbackID',
    'KubeCon Seattle 2024 Group Logo',
    'def5679',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'Annual Kubernetes conference short summary',
    'in-person',
    :'eventCategoryID',
    :'groupID',
    true,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    null,
    null,
    '123 Main St',
    'New York',
    'US',
    'United States',
    'Convention Center',
    'NY',
    '10001',
    5,
    null,
    true,
    ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326),
    null,

    null
), (
    :'eventCommunityLogoFallbackID',
    'KubeCon Seattle 2024 Community Logo',
    'def5680',
    'Annual Kubernetes conference featuring workshops, talks, and hands-on sessions with industry experts',
    'Annual Kubernetes conference short summary',
    'in-person',
    :'eventCategoryID',
    :'groupNoLogoID',
    true,
    '2024-06-15 09:00:00+00',
    '2024-06-15 17:00:00+00',
    'America/New_York',
    null,
    null,
    '123 Main St',
    'New York',
    'US',
    'United States',
    'Convention Center',
    'NY',
    '10001',
    5,
    null,
    true,
    ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326),
    null,

    null
), (
    :'eventPaidID',
    'KubeCon Seattle 2024 Paid',
    'def5681',
    'Paid summary event',
    'Paid summary event short summary',
    'virtual',
    :'eventCategoryID',
    :'groupID',
    true,
    '2024-06-16 09:00:00+00',
    '2024-06-16 17:00:00+00',
    'America/New_York',
    null,
    null,
    '123 Main St',
    'New York',
    'US',
    'United States',
    'Convention Center',
    'NY',
    '10001',
    20,
    'USD',
    false,
    ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326),
    null,

    null
);

-- Event with registration questions and waitlist enabled
insert into event (
    event_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    published,
    starts_at,
    capacity,
    waitlist_enabled,
    registration_questions
) values (
    :'eventQuestionsID',
    :'groupID',
    'Waitlist Questions Event',
    'waitlist-questions-event',
    'Event for waitlist registration question tests',
    'UTC',
    :'eventCategoryID',
    'in-person',
    true,
    '2030-01-03 10:00:00+00',
    2,
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb
);

-- Event ticket type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'eventPaidID',
    1,
    20,
    'General admission'
);

-- Event ticket price window
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values (
    :'ticketPriceWindowID',
    3000,
    :'ticketTypeID'
);

-- Link meeting to event
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventID',
    'https://meeting.example.com/summary',
    'zoom',
    'secret123',
    'summary-meeting-001'
);

-- Event Attendees
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'attendee1ID', 'confirmed'),
    (:'eventID', :'attendee2ID', 'confirmed'),
    (:'eventID', :'pendingInviteID', 'invitation-pending'),
    (:'eventPaidID', :'activeCheckoutUserID', 'registration-questions-pending'),
    (:'eventPaidID', :'expiredCheckoutUserID', 'registration-questions-pending'),
    (:'eventQuestionsID', :'questionsSeatedUserID', 'confirmed'),
    (:'eventQuestionsID', :'questionsWaitlistUserID', 'registration-questions-pending');

-- Event purchases for pending registration capacity checks
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    3000,
    'USD',
    :'eventPaidID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'activeCheckoutUserID'
), (
    3000,
    'USD',
    :'eventPaidID',
    :'ticketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'expiredCheckoutUserID'
);

-- Event Waitlist
insert into event_waitlist (event_id, user_id)
values (:'eventID', :'waitlistUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return correct event summary data as JSON
select is(
    get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb,
    format('{
        "canceled": false,
        "community_display_name": "Cloud Native Seattle",
        "community_name": "cloud-native-seattle",
        "event_id": "%s",
        "group_category_name": "Technology",
        "group_name": "Seattle Kubernetes Meetup",
        "group_slug": "abc1234",
        "has_registration_questions": false,
        "has_related_events": false,
        "kind": "in-person",
        "name": "KubeCon Seattle 2024",
        "published": true,
        "slug": "def5678",
        "test_event": false,
        "timezone": "America/New_York",
        "attendee_approval_required": false,
        "capacity": 5,
        "description_short": "Annual Kubernetes conference short summary",
        "ends_at": 1718470800,
        "event_series_id": "%s",
        "latitude": 47.6062,
        "logo_url": "https://example.com/event-logo.png",
        "longitude": -122.3321,
        "meeting_join_instructions": "Use your registration name when joining.",
        "meeting_join_url": "https://meeting.example.com/summary",
        "meeting_password": "secret123",
        "remaining_capacity": 3,
        "starts_at": 1718442000,
        "venue_address": "123 Main St",
        "venue_city": "New York",
        "venue_country_code": "US",
        "venue_country_name": "United States",
        "venue_name": "Convention Center",
        "venue_state": "NY",
        "waitlist_count": 1,
        "waitlist_enabled": true,
        "zip_code": "10001"
    }', :'eventID', :'eventSeriesID')::jsonb,
    'Should return correct event summary data as JSON'
);

-- Should indicate whether registration questions are configured
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventQuestionsID'::uuid
        )::jsonb
    )->>'has_registration_questions',
    'true',
    'Should indicate whether registration questions are configured'
);

-- Should include payment currency and normalized ticket types in event summaries
select is(
    jsonb_build_object(
        'payment_currency_code', (
            get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventPaidID'::uuid
            )::jsonb
        )->'payment_currency_code',
        'ticket_types', (
            get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventPaidID'::uuid
            )::jsonb
        )->'ticket_types'
    ),
    format(
        '{
            "payment_currency_code": "USD",
            "ticket_types": [
                {
                    "active": true,
                    "current_price": {
                        "amount_minor": 3000
                    },
                    "event_ticket_type_id": "%s",
                    "order": 1,
                    "price_windows": [
                        {
                            "amount_minor": 3000,
                            "event_ticket_price_window_id": "%s"
                        }
                    ],
                    "remaining_seats": 19,
                    "seats_total": 20,
                    "sold_out": false,
                    "title": "General admission"
                }
            ]
        }',
        :'ticketTypeID', :'ticketPriceWindowID'
    )::jsonb,
    'Should include payment currency and normalized ticket types in event summaries'
);

-- Should include pretty group slug when available
update "group" set slug_pretty = 'seattle-kubernetes' where group_id = :'groupID';
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb
    )->>'group_slug_pretty',
    'seattle-kubernetes',
    'Should include pretty group slug when available'
);
update "group" set slug_pretty = null where group_id = :'groupID';

-- Should use group logo when event has no logo
select is(
    (get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventGroupLogoFallbackID'::uuid
    )::jsonb)->>'logo_url',
    'https://example.com/group-logo.png',
    'Should use group logo when event has no logo'
);

-- Should use community logo when event and group have no logo
select is(
    (get_event_summary(
        :'communityID'::uuid,
        :'groupNoLogoID'::uuid,
        :'eventCommunityLogoFallbackID'::uuid
    )::jsonb)->>'logo_url',
    'https://example.com/logo.png',
    'Should use community logo when event and group have no logo'
);

-- Should return null for non-existent event ID
select ok(
    get_event_summary(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'unknownEventID'::uuid
    ) is null,
    'Should return null for non-existent event ID'
);

-- Should return null when group does not match event
select ok(
    get_event_summary(
        :'communityID'::uuid,
        :'unknownGroupID'::uuid,
        :'eventID'::uuid
    ) is null,
    'Should return null when group does not match event'
);

-- Should return null when community does not match event
select ok(
    get_event_summary(
        :'unknownCommunityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    ) is null,
    'Should return null when community does not match event'
);

-- Should count pending registration rows in event capacity summaries
select is(
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventQuestionsID'::uuid)::jsonb->>'remaining_capacity',
    '0',
    'Should count pending registration rows in event capacity summaries'
);

-- Should exclude expired checkout holds from event capacity summaries
select is(
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb->>'remaining_capacity',
    '19',
    'Should exclude expired checkout holds from event capacity summaries'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
