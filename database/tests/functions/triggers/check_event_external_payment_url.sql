-- Tests clearing an event's external payment URL while external holds exist.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeID 'ab190000-0000-0000-0000-000000000001'
\set communityID 'ab190000-0000-0000-0000-000000000002'
\set eventCategoryID 'ab190000-0000-0000-0000-000000000003'
\set groupCategoryID 'ab190000-0000-0000-0000-000000000004'
\set groupID 'ab190000-0000-0000-0000-000000000005'
\set pendingEventID 'ab190000-0000-0000-0000-000000000006'
\set pendingPurchaseID 'ab190000-0000-0000-0000-000000000007'
\set pendingTicketTypeID 'ab190000-0000-0000-0000-000000000008'
\set settledEventID 'ab190000-0000-0000-0000-000000000009'
\set settledPurchaseID 'ab190000-0000-0000-0000-00000000000a'
\set settledTicketTypeID 'ab190000-0000-0000-0000-00000000000b'

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
    'external-url-community',
    'External URL Community',
    'Community for external payment url trigger tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Attendee holding the external purchases
insert into "user" (user_id, auth_hash, email, email_verified, username)
values (:'attendeeID', 'hash-attendee', 'attendee@example.test', true, 'external-url-attendee');

-- Event category used by both events
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category used by the hosting group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (:'groupID', :'communityID', :'groupCategoryID', 'External URL Group', 'external-url-group');

-- Event with a pending external hold
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    :'pendingEventID',
    'Event with a pending external purchase',
    :'eventCategoryID',
    'virtual',
    'https://pay.example.test/pending',
    :'groupID',
    'Pending External Event',
    'KRW',
    'pending-external-event',
    'UTC'
);

-- Event whose external purchases are all settled
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    external_payment_url,
    group_id,
    name,
    payment_currency_code,
    slug,
    timezone
) values (
    :'settledEventID',
    'Event with settled external purchases',
    :'eventCategoryID',
    'virtual',
    'https://pay.example.test/settled',
    :'groupID',
    'Settled External Event',
    'KRW',
    'settled-external-event',
    'UTC'
);

-- Paid ticket tier for the pending event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'pendingTicketTypeID', :'pendingEventID', 1, 10, 'General admission');

-- Paid ticket tier for the settled event
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values (:'settledTicketTypeID', :'settledEventID', 1, 10, 'General admission');

-- Pending external purchase that blocks clearing the URL
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    'KRW',
    :'pendingEventID',
    :'pendingPurchaseID',
    :'pendingTicketTypeID',
    current_timestamp + interval '2 days',
    0,
    0,
    'pending',
    'General admission',
    :'attendeeID'
);

-- Completed external purchase that no longer blocks clearing the URL
insert into event_purchase (
    amount_minor,
    charge_model,
    completed_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_details,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    5000,
    'external',
    current_timestamp - interval '1 hour',
    'KRW',
    :'settledEventID',
    :'settledPurchaseID',
    :'settledTicketTypeID',
    'paid by transfer',
    0,
    0,
    'completed',
    'General admission',
    :'attendeeID'
);

-- Positive price window for the pending event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (5000, gen_random_uuid(), :'pendingTicketTypeID');

-- Positive price window for the settled event
insert into event_ticket_price_window (amount_minor, event_ticket_price_window_id, event_ticket_type_id)
values (5000, gen_random_uuid(), :'settledTicketTypeID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should allow clearing the URL when no external purchase is pending
select lives_ok(
    format(
        $$update event set external_payment_url = null where event_id = %L::uuid$$,
        :'settledEventID'
    ),
    'Should allow clearing the URL when no external purchase is pending'
);

select is(
    (select external_payment_url from event where event_id = :'settledEventID'),
    null,
    'Should persist the cleared URL when no external purchase is pending'
);

-- Should allow replacing the URL while external purchases are pending
select lives_ok(
    format(
        $$update event set external_payment_url = 'https://pay.example.test/updated' where event_id = %L::uuid$$,
        :'pendingEventID'
    ),
    'Should allow replacing the URL while external purchases are pending'
);

-- Should allow saving the event without touching the URL while holds are pending
select lives_ok(
    format(
        $$update event set external_payment_url = external_payment_url where event_id = %L::uuid$$,
        :'pendingEventID'
    ),
    'Should allow saving the event without touching the URL while holds are pending'
);

-- Should reject clearing the URL while an external purchase is pending
select throws_ok(
    format(
        $$update event set external_payment_url = null where event_id = %L::uuid$$,
        :'pendingEventID'
    ),
    'OCG01',
    'external payment url cannot be cleared while pending external purchases exist',
    'Should reject clearing the URL while an external purchase is pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
