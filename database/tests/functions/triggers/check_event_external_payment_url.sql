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

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'attendeeID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

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
select fx_event_ticket_type(:'pendingTicketTypeID', :'pendingEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Paid ticket tier for the settled event
select fx_event_ticket_type(:'settledTicketTypeID', :'settledEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

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
select fx_event_ticket_price_window(gen_random_uuid(), :'pendingTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Positive price window for the settled event
select fx_event_ticket_price_window(gen_random_uuid(), :'settledTicketTypeID', jsonb_build_object('amount_minor', 5000));

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
