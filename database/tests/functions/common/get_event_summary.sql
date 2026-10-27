-- Tests returning event summary information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(23);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeCheckoutUserID '0c090000-0000-0000-0000-000000000001'
\set attendee1ID '0c090000-0000-0000-0000-000000000002'
\set attendee2ID '0c090000-0000-0000-0000-000000000003'
\set communityID '0c090000-0000-0000-0000-000000000004'
\set eventCategoryID '0c090000-0000-0000-0000-000000000005'
\set eventCommunityLogoFallbackID '0c090000-0000-0000-0000-000000000006'
\set eventDeletedSiblingID '0c090000-0000-0000-0000-000000000021'
\set eventExternalID '0c090000-0000-0000-0000-00000000001d'
\set eventGroupLogoFallbackID '0c090000-0000-0000-0000-000000000007'
\set eventID '0c090000-0000-0000-0000-000000000008'
\set eventMeetingDisabledID '0c090000-0000-0000-0000-00000000001e'
\set eventMeetingDisabledNoUrlID '0c090000-0000-0000-0000-00000000001f'
\set eventMeetingMatchingUrlID '0c090000-0000-0000-0000-000000000028'
\set eventMeetingRequestedID '0c090000-0000-0000-0000-000000000020'
\set eventMeetingUnsetRequestID '0c090000-0000-0000-0000-000000000029'
\set eventNoSeriesID '0c090000-0000-0000-0000-000000000022'
\set eventOnlyDeletedSiblingsID '0c090000-0000-0000-0000-000000000023'
\set eventPaidID '0c090000-0000-0000-0000-000000000009'
\set eventQuestionsID '0c090000-0000-0000-0000-00000000000a'
\set eventSeriesDeletedSiblingID '0c090000-0000-0000-0000-000000000024'
\set eventSeriesID '0c090000-0000-0000-0000-00000000000b'
\set eventSeriesWithSiblingID '0c090000-0000-0000-0000-000000000025'
\set eventSiblingID '0c090000-0000-0000-0000-000000000026'
\set eventWithSiblingID '0c090000-0000-0000-0000-000000000027'
\set groupCategoryID '0c090000-0000-0000-0000-00000000000d'
\set groupID '0c090000-0000-0000-0000-00000000000e'
\set groupNoLogoID '0c090000-0000-0000-0000-00000000000f'
\set mainTicketTypeID '0c090000-0000-0000-0000-00000000001c'
\set pendingInviteID '0c090000-0000-0000-0000-000000000010'
\set privateTicketPriceWindowID '0c090000-0000-0000-0000-00000000001a'
\set privateTicketTypeID '0c090000-0000-0000-0000-00000000001b'
\set questionID '0c090000-0000-0000-0000-000000000011'
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

-- User holding an active checkout for the paid event
select fx_user(:'activeCheckoutUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));

-- First confirmed attendee counted against the main event capacity
select fx_user(:'attendee1ID', jsonb_build_object(
    'created_at', '2024-01-01 00:00:00+00',
    'username', 'attendee1'
));

-- Second confirmed attendee counted against the main event capacity
select fx_user(:'attendee2ID', jsonb_build_object(
    'created_at', '2024-01-01 00:00:00+00',
    'username', 'attendee2'
));

-- User with a pending invitation to the main event
select fx_user(:'pendingInviteID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));

-- User waiting on the main event waitlist
select fx_user(:'waitlistUserID', jsonb_build_object('created_at', '2024-01-01 00:00:00+00'));

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Technology'));

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'logo_url', 'https://example.com/group-logo.png',
    'name', 'Seattle Kubernetes Meetup',
    'slug', 'abc1234',
    'slug_pretty', 'seattle-kubernetes'
));

-- Group without a logo
select fx_group(:'groupNoLogoID', :'communityID', :'groupCategoryID');

-- Event series whose only other event is deleted
select fx_event_series(:'eventSeriesDeletedSiblingID', :'groupID');

-- Event series containing only the summarized event
select fx_event_series(:'eventSeriesID', :'groupID');

-- Event series with two live events
select fx_event_series(:'eventSeriesWithSiblingID', :'groupID');

-- Event whose manual join URL matches its linked meeting
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'description_short', 'Annual Kubernetes conference short summary',
    'ends_at', '2024-06-15 17:00:00+00',
    'event_series_id', :'eventSeriesID',
    'location', ST_GeogFromText('POINT(-122.3321 47.6062)'),
    'logo_url', 'https://example.com/event-logo.png',
    'meeting_join_instructions', 'Use your registration name when joining.',
    'meeting_join_url', 'https://meeting.example.com/summary',
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

-- Event without a logo that falls back to the group logo
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

-- Event without a logo in a group without a logo
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

-- Paid event with public and invitation-only ticket types
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

-- Event with registration questions and a registration window
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
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
    'starts_at', '2030-01-03 10:00:00+00'
));

-- Event that collects payment outside the platform
select fx_event(:'eventExternalID', :'groupID', :'eventCategoryID', jsonb_build_object('external_payment_url', 'https://pay.example.test/summary'));

-- Event whose disabled meeting awaits deletion and has a manual link
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at
) values (
    :'eventMeetingDisabledID',
    'An event used to verify the projected meeting join URL',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Disabled Meeting Event',
    'event-summary-meeting-disabled',
    'UTC',

    100,
    '2024-06-21 11:00:00+00',
    false,
    'https://meet.example.com/summary-manual',
    'zoom',
    false,
    true,
    '2024-06-21 09:00:00+00'
);

-- Event whose disabled meeting awaits deletion without a manual link
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at
) values (
    :'eventMeetingDisabledNoUrlID',
    'An event used to verify the projected meeting join URL',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Disabled Meeting Without Link Event',
    'event-summary-meeting-disabled-no-url',
    'UTC',

    100,
    '2024-06-22 11:00:00+00',
    false,
    null,
    'zoom',
    false,
    true,
    '2024-06-22 09:00:00+00'
);

-- Event whose disabled meeting was kept because its manual link is the provider link
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at
) values (
    :'eventMeetingMatchingUrlID',
    'An event used to verify the projected meeting password',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Matching Meeting Link Event',
    'event-summary-meeting-matching-url',
    'UTC',

    100,
    '2024-06-23 11:00:00+00',
    null,
    'https://meeting.example.com/summary-matching-url',
    'zoom',
    false,
    true,
    '2024-06-23 09:00:00+00'
);

-- Event with a requested meeting
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at
) values (
    :'eventMeetingRequestedID',
    'An event used to verify the projected meeting join URL',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Requested Meeting Event',
    'event-summary-meeting-requested',
    'UTC',

    100,
    '2024-06-19 11:00:00+00',
    true,
    null,
    'zoom',
    true,
    true,
    '2024-06-19 09:00:00+00'
);

-- Event whose meeting with an unset request awaits deletion and has a manual link
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone,

    capacity,
    ends_at,
    meeting_in_sync,
    meeting_join_url,
    meeting_provider_id,
    meeting_requested,
    published,
    starts_at
) values (
    :'eventMeetingUnsetRequestID',
    'An event used to verify the projected meeting password',
    :'eventCategoryID',
    'virtual',
    :'groupID',
    'Unset Meeting Request Event',
    'event-summary-meeting-unset-request',
    'UTC',

    100,
    '2024-06-24 11:00:00+00',
    false,
    'https://meet.example.com/summary-manual-unset-request',
    'zoom',
    null,
    true,
    '2024-06-24 09:00:00+00'
);

-- Deleted event in the series whose only other event is deleted
select fx_event(:'eventDeletedSiblingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'deleted', true,
    'event_series_id', :'eventSeriesDeletedSiblingID'
));

-- Event outside any series
select fx_event(:'eventNoSeriesID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', null));

-- Event whose only series sibling is deleted
select fx_event(:'eventOnlyDeletedSiblingsID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesDeletedSiblingID'));

-- Live sibling in the series with two live events
select fx_event(:'eventSiblingID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesWithSiblingID'));

-- Event with a live sibling in its series
select fx_event(:'eventWithSiblingID', :'groupID', :'eventCategoryID', jsonb_build_object('event_series_id', :'eventSeriesWithSiblingID'));

-- Attendees occupying main event seats and a paid event registration
insert into event_attendee (event_id, user_id, status)
values
    (:'eventID', :'attendee1ID', 'confirmed'),
    (:'eventID', :'attendee2ID', 'confirmed'),
    (:'eventID', :'pendingInviteID', 'invitation-pending'),
    (:'eventPaidID', :'activeCheckoutUserID', 'registration-questions-pending');

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

-- Invitation-only ticket type excluded from public summaries
select fx_event_ticket_type(:'privateTicketTypeID', :'eventPaidID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 5
));

-- Link meeting to event
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventID',
    'https://meeting.example.com/summary',
    'zoom',
    'secret123',
    'summary-meeting-001'
);

-- Provider meeting of the event awaiting meeting deletion with a manual link
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventMeetingDisabledID',
    'https://meeting.example.com/summary-disabled',
    'zoom',
    'summary-meeting-disabled-001-secret',
    'summary-meeting-disabled-001'
);

-- Provider meeting of the event awaiting meeting deletion without a manual link
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventMeetingDisabledNoUrlID',
    'https://meeting.example.com/summary-disabled-no-url',
    'zoom',
    'summary-meeting-disabled-no-url-001-secret',
    'summary-meeting-disabled-no-url-001'
);

-- Provider meeting of the event whose manual link is the provider link
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventMeetingMatchingUrlID',
    'https://meeting.example.com/summary-matching-url',
    'zoom',
    'summary-meeting-matching-url-001-secret',
    'summary-meeting-matching-url-001'
);

-- Provider meeting of the event with a requested meeting
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventMeetingRequestedID',
    'https://meeting.example.com/summary-requested',
    'zoom',
    'summary-meeting-requested-001-secret',
    'summary-meeting-requested-001'
);

-- Provider meeting of the event with an unset meeting request awaiting deletion
insert into meeting (event_id, join_url, meeting_provider_id, password, provider_meeting_id)
values (
    :'eventMeetingUnsetRequestID',
    'https://meeting.example.com/summary-unset-request',
    'zoom',
    'summary-meeting-unset-request-001-secret',
    'summary-meeting-unset-request-001'
);

-- Active checkout hold counted in the ticket type remaining seats
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
);

-- Current free price for the main event's invitation-only tier
select fx_event_ticket_price_window(gen_random_uuid(), :'mainTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Event ticket price window
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 3000));

-- Current invitation-only ticket price excluded from public summaries
select fx_event_ticket_price_window(:'privateTicketPriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 1000));

-- Main event waitlist entry
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
        "cohosts": [],
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
        "venue_zip_code": "10001",
        "waitlist_count": 1,
        "waitlist_enabled": true,
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

-- Should ignore deleted events in the series when reporting related events
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventOnlyDeletedSiblingsID'::uuid
        )::jsonb
    )->>'has_related_events',
    'false',
    'Should ignore deleted events in the series when reporting related events'
);

-- Should report no related events for an event alone in its series
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb
    )->>'has_related_events',
    'false',
    'Should report no related events for an event alone in its series'
);

-- Should report no related events for an event outside any series
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventNoSeriesID'::uuid
        )::jsonb
    )->>'has_related_events',
    'false',
    'Should report no related events for an event outside any series'
);

-- Should report related events when another live event shares the series
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventWithSiblingID'::uuid
        )::jsonb
    )->>'has_related_events',
    'true',
    'Should report related events when another live event shares the series'
);

-- Should include configured registration window timestamps in event summaries
select is(
    (
        with payload as (
            select get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventQuestionsID'::uuid
            )::jsonb as event_json
        )
        select jsonb_build_object(
            'registration_ends_at', event_json->'registration_ends_at',
            'registration_starts_at', event_json->'registration_starts_at'
        )
        from payload
    ),
    jsonb_build_object(
        'registration_ends_at', floor(extract(epoch from '2030-01-02 10:00:00+00'::timestamptz)),
        'registration_starts_at', floor(extract(epoch from '2030-01-01 10:00:00+00'::timestamptz))
    ),
    'Should include configured registration window timestamps in event summaries'
);

-- Should include payment currency and normalized ticket types in event summaries
select is(
    (
        with payload as (
            select get_event_summary(
                :'communityID'::uuid,
                :'groupID'::uuid,
                :'eventPaidID'::uuid
            )::jsonb as event_json
        )
        select jsonb_build_object(
            'payment_currency_code', event_json->'payment_currency_code',
            'ticket_types', event_json->'ticket_types'
        )
        from payload
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

-- Should omit the join URL when the event meeting is no longer requested without a manual URL
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingDisabledNoUrlID'::uuid
        )::jsonb
    ) ? 'meeting_join_url',
    false,
    'Should omit the join URL when the event meeting is no longer requested without a manual URL'
);

-- Should return the provider join URL while the event meeting is requested
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingRequestedID'::uuid
        )::jsonb
    )->>'meeting_join_url',
    'https://meeting.example.com/summary-requested',
    'Should return the provider join URL while the event meeting is requested'
);

-- Should return the stored manual join URL when the event meeting is no longer requested
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingDisabledID'::uuid
        )::jsonb
    )->>'meeting_join_url',
    'https://meet.example.com/summary-manual',
    'Should return the stored manual join URL when the event meeting is no longer requested'
);

-- Should omit the meeting password when the event meeting is no longer requested with an unrelated manual URL
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingDisabledID'::uuid
        )::jsonb
    ) ? 'meeting_password',
    false,
    'Should omit the meeting password when the event meeting is no longer requested with an unrelated manual URL'
);

-- Should omit the meeting password when the event meeting is no longer requested without a manual URL
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingDisabledNoUrlID'::uuid
        )::jsonb
    ) ? 'meeting_password',
    false,
    'Should omit the meeting password when the event meeting is no longer requested without a manual URL'
);

-- Should omit the meeting password when the event meeting request is unset with an unrelated manual URL
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingUnsetRequestID'::uuid
        )::jsonb
    ) ? 'meeting_password',
    false,
    'Should omit the meeting password when the event meeting request is unset with an unrelated manual URL'
);

-- Should return the meeting password when the manual join URL of a no longer requested event meeting is the provider link
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingMatchingUrlID'::uuid
        )::jsonb
    )->>'meeting_password',
    'summary-meeting-matching-url-001-secret',
    'Should return the meeting password when the manual join URL of a no longer requested event meeting is the provider link'
);

-- Should return the meeting password while the event meeting is requested
select is(
    (
        get_event_summary(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventMeetingRequestedID'::uuid
        )::jsonb
    )->>'meeting_password',
    'summary-meeting-requested-001-secret',
    'Should return the meeting password while the event meeting is requested'
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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
