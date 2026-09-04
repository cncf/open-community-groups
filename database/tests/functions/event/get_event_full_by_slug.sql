-- Tests returning public full event information by slug.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e060000-0000-0000-0000-000000000001'
\set eventCanceledID '5e060000-0000-0000-0000-000000000002'
\set eventCategoryID '5e060000-0000-0000-0000-000000000003'
\set eventDeletedID '5e060000-0000-0000-0000-000000000004'
\set eventDraftCanceledID '5e060000-0000-0000-0000-000000000005'
\set eventID '5e060000-0000-0000-0000-000000000006'
\set eventPaidID '5e060000-0000-0000-0000-000000000007'
\set groupCategoryID '5e060000-0000-0000-0000-000000000008'
\set groupID '5e060000-0000-0000-0000-000000000009'
\set sponsor1ID '5e060000-0000-0000-0000-00000000000a'
\set sponsor2ID '5e060000-0000-0000-0000-00000000000b'
\set ticketPrivatePriceWindowID '5e060000-0000-0000-0000-000000000012'
\set ticketPrivateTypeID '5e060000-0000-0000-0000-000000000013'
\set ticketPriceWindowID '5e060000-0000-0000-0000-00000000000c'
\set ticketTypeID '5e060000-0000-0000-0000-00000000000d'
\set user1ID '5e060000-0000-0000-0000-00000000000e'
\set user2ID '5e060000-0000-0000-0000-00000000000f'
\set user3ID '5e060000-0000-0000-0000-000000000010'
\set user4ID '5e060000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and event categories
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');

-- Users with scenario-specific state
select fx_user(:'user1ID', jsonb_build_object(
    'bio', 'Conference opening speaker',
    'company', 'Tech Corp',
    'created_at', '2024-01-01 00:00:00'
));
select fx_user(:'user2ID', jsonb_build_object(
    'bio', 'Community host and emcee',
    'company', 'Dev Inc',
    'created_at', '2024-01-01 00:00:00'
));
select fx_user(:'user3ID', jsonb_build_object(
    'bio', 'Community programs lead',
    'company', 'Cloud Co',
    'created_at', '2024-01-01 00:00:00'
));
select fx_user(:'user4ID', jsonb_build_object(
    'bio', 'Operations and logistics manager',
    'company', 'StartUp',
    'created_at', '2024-01-01 00:00:00'
));

-- Group with scenario-specific state
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'created_at', '2025-02-11 10:00:00+00',
    'slug', 'abc1234',
    'slug_pretty', 'test-group-pretty'
));

-- Event with scenario-specific state
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 500,
    'ends_at', '2024-06-15 17:00:00+00',
    'event_kind_id', 'hybrid',
    'luma_url', 'https://luma.com/event123',
    'meeting_in_sync', true,
    'meeting_join_url', 'https://stream.example.com/live',
    'meeting_recording_url', 'https://youtube.com/watch?v=123',
    'meeting_requested', false,
    'meetup_url', 'https://meetup.com/event123',
    'photos_urls', array['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
    'published', true,
    'slug', 'def5678',
    'starts_at', '2024-06-15 09:00:00+00',
    'tags', array['technology', 'conference', 'workshops'],
    'timezone', 'America/New_York',
    'venue_address', '123 Main St',
    'venue_city', 'New York',
    'venue_name', 'Convention Center',
    'venue_zip_code', '10001'
));

-- Published paid event returned with ticketing details
select fx_event(:'eventPaidID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true,
    'slug', 'paid-tech-conference-2024',
    'starts_at', '2024-06-16 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Published canceled event available by slug
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'event_kind_id', 'virtual',
    'published', true,
    'slug', 'canceled-tech-conference-2024',
    'starts_at', '2024-06-17 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Unpublished canceled event excluded from public lookup
select fx_event(:'eventDraftCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'event_kind_id', 'virtual',
    'slug', 'canceled-draft-tech-conference-2024',
    'starts_at', '2024-06-19 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Deleted event excluded from public lookup
select fx_event(:'eventDeletedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'deleted', true,
    'event_kind_id', 'virtual',
    'slug', 'deleted-tech-conference-2024',
    'starts_at', '2024-06-18 09:00:00+00',
    'timezone', 'America/New_York'
));

-- Event ticket type with scenario-specific state
select fx_event_ticket_type(:'ticketTypeID', :'eventPaidID', jsonb_build_object('seats_total', 40));

-- Invitation-only ticket type excluded from the public slug contract
select fx_event_ticket_type(:'ticketPrivateTypeID', :'eventPaidID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 10
));

-- Event ticket price window with scenario-specific state
select fx_event_ticket_price_window(:'ticketPriceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 2500));

-- Invitation-only ticket price excluded from the public slug contract
select fx_event_ticket_price_window(:'ticketPrivatePriceWindowID', :'ticketPrivateTypeID', jsonb_build_object('amount_minor', 1000));

-- Event Host
insert into event_host (event_id, user_id, created_at)
values
    (:'eventID', :'user1ID', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', '2024-01-01 00:00:00');

-- Event Speakers
insert into event_speaker (event_id, user_id, featured, created_at)
values
    (:'eventID', :'user1ID', false, '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', true, '2024-01-01 00:00:00'),
    (:'eventID', :'user3ID', false, '2024-01-01 00:00:00');

-- Event Attendee
insert into event_attendee (event_id, user_id, checked_in, checked_in_at, created_at)
values
    (:'eventID', :'user1ID', true, '2024-01-01 00:00:00', '2024-01-01 00:00:00'),
    (:'eventID', :'user2ID', false, null, '2024-01-01 00:00:00');

-- Group Team
insert into group_team (group_id, user_id, role, accepted, "order", created_at)
values
    (:'groupID', :'user3ID', 'admin', true, 1, '2024-01-01 00:00:00'),
    (:'groupID', :'user4ID', 'admin', true, 2, '2024-01-01 00:00:00');

-- Group Sponsors
insert into group_sponsor (group_sponsor_id, group_id, name, logo_url, website_url)
values
    (:'sponsor1ID', :'groupID', 'CloudInc', 'https://example.com/cloudinc.png', null),
    (
        :'sponsor2ID',
        :'groupID',
        'TechCorp',
        'https://example.com/techcorp.png',
        'https://techcorp.com'
    );

-- Event Sponsors (linking group sponsors to event)
insert into event_sponsor (event_id, group_sponsor_id, level)
values
    (:'eventID', :'sponsor1ID', 'Silver'),
    (:'eventID', :'sponsor2ID', 'Gold');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the same payload as get_event_full
select is(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'def5678')::jsonb,
    get_public_event_full(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should return the same payload as get_event_full'
);

-- Should return null with non-existing event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'non-existing-event') is null,
    'Should return null with non-existing event slug'
);

-- Should return a canceled event when it remains published
select is(
    get_event_full_by_slug(
        :'communityID'::uuid,
        'abc1234',
        'canceled-tech-conference-2024'
    )::jsonb,
    get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventCanceledID'::uuid
    )::jsonb,
    'Should return a canceled event when it remains published'
);

-- Should return null with canceled draft event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'canceled-draft-tech-conference-2024') is null,
    'Should return null with canceled draft event slug'
);

-- Should return null with deleted event slug
select ok(
    get_event_full_by_slug(:'communityID'::uuid, 'abc1234', 'deleted-tech-conference-2024') is null,
    'Should return null with deleted event slug'
);

-- Should return the public paid-event payload
select is(
    get_event_full_by_slug(
        :'communityID'::uuid,
        'abc1234',
        'paid-tech-conference-2024'
    )::jsonb,
    get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventPaidID'::uuid
    )::jsonb,
    'Should return the public paid-event payload'
);

-- Should exclude invitation-only ticket types from public slug responses
select is(
    jsonb_array_length(
        get_event_full_by_slug(
            :'communityID'::uuid,
            'abc1234',
            'paid-tech-conference-2024'
        )::jsonb->'ticket_types'
    ),
    1,
    'Should exclude invitation-only ticket types from public slug responses'
);

-- Should resolve event by group pretty slug
select is(
    get_event_full_by_slug(:'communityID'::uuid, 'test-group-pretty', 'def5678')::jsonb,
get_public_event_full(:'communityID'::uuid, :'groupID'::uuid, :'eventID'::uuid)::jsonb,
    'Should resolve event by group pretty slug'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
