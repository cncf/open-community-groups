-- Tests returning event summary information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(13);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCheckoutUserID '0c090000-0000-0000-0000-000000000001'
\set attendee1ID '0c090000-0000-0000-0000-000000000002'
\set attendee2ID '0c090000-0000-0000-0000-000000000003'
\set communityID '0c090000-0000-0000-0000-000000000004'
\set eventCategoryID '0c090000-0000-0000-0000-000000000005'
\set eventCommunityLogoFallbackID '0c090000-0000-0000-0000-000000000006'
\set eventExternalID '0c090000-0000-0000-0000-00000000001d'
\set eventGroupLogoFallbackID '0c090000-0000-0000-0000-000000000007'
\set eventID '0c090000-0000-0000-0000-000000000008'
\set eventPaidID '0c090000-0000-0000-0000-000000000009'
\set eventQuestionsID '0c090000-0000-0000-0000-00000000000a'
\set eventSeriesID '0c090000-0000-0000-0000-00000000000b'
\set expiredCheckoutUserID '0c090000-0000-0000-0000-00000000000c'
\set groupCategoryID '0c090000-0000-0000-0000-00000000000d'
\set groupID '0c090000-0000-0000-0000-00000000000e'
\set groupNoLogoID '0c090000-0000-0000-0000-00000000000f'
\set mainTicketTypeID '0c090000-0000-0000-0000-00000000001c'
\set pendingInviteID '0c090000-0000-0000-0000-000000000010'
\set privateTicketPriceWindowID '0c090000-0000-0000-0000-00000000001a'
\set privateTicketTypeID '0c090000-0000-0000-0000-00000000001b'
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
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Cloud Native Seattle Event Summary',
    'logo_url', 'https://example.com/logo.png',
    'name', 'cloud-native-seattle-event-summary'
));

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Technology'));

-- Baseline event categories and groups
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupNoLogoID', :'communityID', :'groupCategoryID');

-- Attendees for remaining capacity verification
select fx_user(:'attendee1ID', jsonb_build_object(
    'created_at', '2024-01-01 00:00:00+00',
    'username', 'attendee1'
));
select fx_user(:'attendee2ID', jsonb_build_object(
    'created_at', '2024-01-01 00:00:00+00',
    'username', 'attendee2'
));
select fx_user(:'waitlistUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));
select fx_user(:'pendingInviteID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));
select fx_user(:'expiredCheckoutUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));
select fx_user(:'activeCheckoutUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));
select fx_user(:'questionsSeatedUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));
select fx_user(:'questionsWaitlistUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://example.com/group-logo.png',
    'name', 'Seattle Kubernetes Meetup',
    'slug', 'abc1234',
    'slug_pretty', 'seattle-kubernetes'
));

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
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'description_short', 'Annual Kubernetes conference short summary',
    'ends_at', '2024-06-15 17:00:00+00',
    'event_series_id', :'eventSeriesID',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'logo_url', 'https://example.com/event-logo.png',
    'meeting_join_instructions', 'Use your registration name when joining.',
    'name', 'KubeCon Seattle 2024',
    'published', true,
    'slug', 'def5678',
    'starts_at', '2024-06-15 09:00:00+00',
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Convention Center',
    'venue_state_code', 'NY',
    'venue_state_name', 'New York',
    'venue_zip_code', '10001',
    'waitlist_enabled', true
));
select fx_event(:'eventGroupLogoFallbackID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'description_short', 'Annual Kubernetes conference short summary',
    'ends_at', '2024-06-15 17:00:00+00',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'published', true,
    'starts_at', '2024-06-15 09:00:00+00',
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Convention Center',
    'venue_state_code', 'NY',
    'venue_state_name', 'New York',
    'venue_zip_code', '10001',
    'waitlist_enabled', true
));
select fx_event(:'eventCommunityLogoFallbackID', :'groupNoLogoID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'description_short', 'Annual Kubernetes conference short summary',
    'ends_at', '2024-06-15 17:00:00+00',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'published', true,
    'starts_at', '2024-06-15 09:00:00+00',
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Convention Center',
    'venue_state_code', 'NY',
    'venue_state_name', 'New York',
    'venue_zip_code', '10001',
    'waitlist_enabled', true
));
select fx_event(:'eventPaidID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 20,
    'ends_at', '2024-06-16 17:00:00+00',
    'event_kind_id', 'virtual',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2024-06-16 09:00:00+00',
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_country_code', 'US',
    'venue_country_name', 'United States',
    'venue_name', 'Convention Center',
    'venue_state_code', 'NY',
    'venue_state_name', 'New York',
    'venue_zip_code', '10001'
));

-- Event with registration questions and waitlist enabled
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 2,
    'published', true,
    'registration_ends_at', '2030-01-02 10:00:00+00',
    'registration_questions', jsonb_build_array(jsonb_build_object(
        'id', :'questionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    'registration_starts_at', '2030-01-01 10:00:00+00',
    'starts_at', '2030-01-03 10:00:00+00',
    'waitlist_enabled', true
));

-- Event that collects payment outside the platform
select fx_event(:'eventExternalID', :'groupID', :'eventCategoryID', jsonb_build_object('external_payment_url', 'https://pay.example.test/summary'));

-- Event ticket type
select fx_event_ticket_type(:'ticketTypeID', :'eventPaidID', jsonb_build_object(
    'seats_total', 20,
    'title', 'General admission'
));

-- Invitation-only tier used by the main event's queue fixture
select fx_event_ticket_type(:'mainTicketTypeID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 5,
    'title', 'General admission'
));

-- Current free price for the main event's invitation-only tier
select fx_event_ticket_price_window(gen_random_uuid(), :'mainTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Invitation-only ticket type excluded from public summaries
select fx_event_ticket_type(:'privateTicketTypeID', :'eventPaidID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 5
));

-- Event ticket price window
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 3000));

-- Current invitation-only ticket price excluded from public summaries
select fx_event_ticket_price_window(:'privateTicketPriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 1000));

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
    0,
    'USD',
    :'eventPaidID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'activeCheckoutUserID'
), (
    0,
    'USD',
    :'eventPaidID',
    :'ticketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'expiredCheckoutUserID'
);

-- Event Waitlist
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'mainTicketTypeID', :'waitlistUserID');

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
        "community_display_name": "Cloud Native Seattle Event Summary",
        "community_name": "cloud-native-seattle-event-summary",
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
        "venue_state_code": "NY",
        "venue_state_name": "New York",
        "waitlist_count": 1,
        "waitlist_enabled": true,
        "zip_code": "10001",
        "group_slug_pretty": "seattle-kubernetes"
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

-- Should mark summaries that collect payment outside the platform
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventExternalID'::uuid
        )::jsonb
    )->>'has_external_payment',
    'true',
    'Should mark summaries that collect payment outside the platform'
);

-- Should include configured registration window timestamps in event summaries
select is(
    jsonb_build_object(
        'registration_ends_at', (
            get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventQuestionsID'::uuid
            )::jsonb
        )->'registration_ends_at',
        'registration_starts_at', (
            get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventQuestionsID'::uuid
            )::jsonb
        )->'registration_starts_at'
    ),
    jsonb_build_object(
        'registration_ends_at', floor(extract(epoch from '2030-01-02 10:00:00+00'::timestamptz)),
        'registration_starts_at', floor(extract(epoch from '2030-01-01 10:00:00+00'::timestamptz))
    ),
    'Should include configured registration window timestamps in event summaries'
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
                    "availability": "public",
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

-- Should exclude pending registration rows without an active checkout hold
select is(
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventQuestionsID'::uuid)::jsonb->>'remaining_capacity',
    '1',
    'Should exclude pending registration rows without an active checkout hold'
);

-- Should exclude expired checkout holds from event capacity summaries
select is(
    get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb->>'remaining_capacity',
    '24',
    'Should exclude expired checkout holds from event capacity summaries'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
