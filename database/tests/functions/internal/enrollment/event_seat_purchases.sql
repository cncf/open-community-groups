-- Tests resolving the purchase holding each attendee's seat for an event.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5eab0000-0000-0000-0000-000000000001'
\set completedFallbackNewerPurchaseID '5eab0000-0000-0000-0000-000000000002'
\set completedFallbackOlderPurchaseID '5eab0000-0000-0000-0000-000000000003'
\set completedFallbackUserID '5eab0000-0000-0000-0000-000000000004'
\set eventCategoryID '5eab0000-0000-0000-0000-000000000005'
\set eventID '5eab0000-0000-0000-0000-000000000006'
\set groupCategoryID '5eab0000-0000-0000-0000-000000000007'
\set groupID '5eab0000-0000-0000-0000-000000000008'
\set ignoredUserID '5eab0000-0000-0000-0000-000000000009'
\set latestCompletedRefundPurchaseID '5eab0000-0000-0000-0000-00000000000a'
\set latestCompletedReplacementPurchaseID '5eab0000-0000-0000-0000-00000000000b'
\set latestCompletedUserID '5eab0000-0000-0000-0000-00000000000c'
\set offerID '5eab0000-0000-0000-0000-00000000000d'
\set offerPurchaseID '5eab0000-0000-0000-0000-00000000000e'
\set offerUserID '5eab0000-0000-0000-0000-00000000000f'
\set otherEventID '5eab0000-0000-0000-0000-000000000010'
\set otherEventUserID '5eab0000-0000-0000-0000-000000000011'
\set otherTicketTypeID '5eab0000-0000-0000-0000-000000000012'
\set ticketTypeID '5eab0000-0000-0000-0000-000000000013'
\set ticketTypeVipID '5eab0000-0000-0000-0000-000000000014'
\set tieCreatedNewerPurchaseID '5eab0000-0000-0000-0000-000000000015'
\set tieCreatedOlderPurchaseID '5eab0000-0000-0000-0000-000000000016'
\set tieCreatedUserID '5eab0000-0000-0000-0000-000000000017'
\set tieIdFirstPurchaseID '5eab0000-0000-0000-0000-000000000018'
\set tieIdSecondPurchaseID '5eab0000-0000-0000-0000-000000000019'
\set tieIdUserID '5eab0000-0000-0000-0000-00000000001a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the events
select fx_community(:'communityID');

-- User with a completed refund in flight and a newer never-completed purchase
select fx_user(:'completedFallbackUserID');

-- User whose purchases never hold a seat
select fx_user(:'ignoredUserID');

-- User with a refund in flight and a completed replacement
select fx_user(:'latestCompletedUserID');

-- User admitted through an admission offer
select fx_user(:'offerUserID');

-- User holding a seat only in the other event
select fx_user(:'otherEventUserID');

-- User whose purchases completed together but were created apart
select fx_user(:'tieCreatedUserID');

-- User whose purchases completed and were created together
select fx_user(:'tieIdUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ticketed event whose seat purchases are resolved
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticketed event whose purchases must be excluded
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD'
));

-- Ticket tier of the other event
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID', jsonb_build_object(
    'title', 'Other'
));

-- General ticket tier of the event
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'title', 'General'
));

-- VIP ticket tier claimed through the admission offer
select fx_event_ticket_type(:'ticketTypeVipID', :'eventID', jsonb_build_object(
    'title', 'VIP'
));

-- Completed admission offer claimed by its purchase
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    ticket_title
) values (
    :'offerID',
    '2024-01-01 10:00:00+00',
    :'eventID',
    :'ticketTypeVipID',
    '2024-01-10 10:00:00+00',
    'approval',
    'completed',
    :'offerUserID',

    0,
    null,
    0,
    'VIP offer'
);

-- Completed refund in flight and a newer late-paid hold that never completed
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (
        :'completedFallbackNewerPurchaseID',
        0,
        '2024-01-04 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Never completed',
        :'completedFallbackUserID',

        null
    ),
    (
        :'completedFallbackOlderPurchaseID',
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Completed refund in flight',
        :'completedFallbackUserID',

        '2024-01-02 10:05:00+00'
    );

-- Pending, expired and refunded purchases that hold no seat
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at,
    hold_expires_at
) values
    (
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refunded',
        'Refunded',
        :'ignoredUserID',

        '2024-01-02 10:05:00+00',
        null
    ),
    (
        0,
        '2024-01-03 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'expired',
        'Expired',
        :'ignoredUserID',

        null,
        null
    ),
    (
        0,
        current_timestamp - interval '1 minute',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'pending',
        'Pending',
        :'ignoredUserID',

        null,
        current_timestamp + interval '10 minutes'
    );

-- Refund in flight and its later completed replacement
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (
        :'latestCompletedRefundPurchaseID',
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Refund in flight',
        :'latestCompletedUserID',

        '2024-01-02 10:05:00+00'
    ),
    (
        :'latestCompletedReplacementPurchaseID',
        0,
        '2024-01-04 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'completed',
        'Replacement',
        :'latestCompletedUserID',

        '2024-01-04 10:05:00+00'
    );

-- Completed purchase claiming the admission offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    admission_offer_id,
    completed_at
) values (
    :'offerPurchaseID',
    0,
    '2024-01-03 10:00:00+00',
    'USD',
    :'eventID',
    :'ticketTypeVipID',
    'completed',
    'VIP offer',
    :'offerUserID',

    :'offerID',
    '2024-01-03 10:05:00+00'
);

-- Completed purchase of the other event
insert into event_purchase (
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values (
    0,
    '2024-01-03 10:00:00+00',
    'USD',
    :'otherEventID',
    :'otherTicketTypeID',
    'completed',
    'Other',
    :'otherEventUserID',

    '2024-01-03 10:05:00+00'
);

-- Purchases completed together but created apart
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (
        :'tieCreatedNewerPurchaseID',
        0,
        '2024-01-03 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Created later',
        :'tieCreatedUserID',

        '2024-01-05 10:00:00+00'
    ),
    (
        :'tieCreatedOlderPurchaseID',
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-recovery-pending',
        'Created earlier',
        :'tieCreatedUserID',

        '2024-01-05 10:00:00+00'
    );

-- Purchases completed and created together
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    created_at,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id,

    completed_at
) values
    (
        :'tieIdFirstPurchaseID',
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-pending',
        'Lower identifier',
        :'tieIdUserID',

        '2024-01-05 10:00:00+00'
    ),
    (
        :'tieIdSecondPurchaseID',
        0,
        '2024-01-02 10:00:00+00',
        'USD',
        :'eventID',
        :'ticketTypeID',
        'refund-recovery-pending',
        'Higher identifier',
        :'tieIdUserID',

        '2024-01-05 10:00:00+00'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should break completed_at ties by created_at, then event_purchase_id
select results_eq(
    format($$
        select sp.event_purchase_id
        from event_seat_purchases(%L::uuid) sp
        where sp.user_id in (%L::uuid, %L::uuid)
        order by sp.user_id
    $$, :'eventID', :'tieCreatedUserID', :'tieIdUserID'),
    format(
        $$ values (%L::uuid), (%L::uuid) $$,
        :'tieCreatedNewerPurchaseID',
        :'tieIdSecondPurchaseID'
    ),
    'Should break completed_at ties by created_at, then event_purchase_id'
);

-- Should exclude purchases of other events
select is(
    (
        select count(*)
        from event_seat_purchases(:'eventID'::uuid) sp
        where sp.user_id = :'otherEventUserID'::uuid
    ),
    0::bigint,
    'Should exclude purchases of other events'
);

-- Should ignore pending, expired and refunded purchases
select is(
    (
        select count(*)
        from event_seat_purchases(:'eventID'::uuid) sp
        where sp.user_id = :'ignoredUserID'::uuid
    ),
    0::bigint,
    'Should ignore pending, expired and refunded purchases'
);

-- Should prefer a completed purchase over a newer never-completed one
select is(
    (
        select sp.event_purchase_id
        from event_seat_purchases(:'eventID'::uuid) sp
        where sp.user_id = :'completedFallbackUserID'::uuid
    ),
    :'completedFallbackOlderPurchaseID'::uuid,
    'Should prefer a completed purchase over a newer never-completed one'
);

-- Should return one row per user with the seat purchase details
select results_eq(
    format($$
        select
            sp.admission_offer_id,
            sp.event_purchase_id,
            sp.event_ticket_type_id,
            sp.ticket_title,
            sp.user_id
        from event_seat_purchases(%L::uuid) sp
        order by sp.user_id
    $$, :'eventID'),
    format(
        $$ values
            (null::uuid, %L::uuid, %L::uuid, 'Completed refund in flight'::text, %L::uuid),
            (null::uuid, %L::uuid, %L::uuid, 'Replacement'::text, %L::uuid),
            (%L::uuid, %L::uuid, %L::uuid, 'VIP offer'::text, %L::uuid),
            (null::uuid, %L::uuid, %L::uuid, 'Created later'::text, %L::uuid),
            (null::uuid, %L::uuid, %L::uuid, 'Higher identifier'::text, %L::uuid)
        $$,
        :'completedFallbackOlderPurchaseID', :'ticketTypeID', :'completedFallbackUserID',
        :'latestCompletedReplacementPurchaseID', :'ticketTypeID', :'latestCompletedUserID',
        :'offerID', :'offerPurchaseID', :'ticketTypeVipID', :'offerUserID',
        :'tieCreatedNewerPurchaseID', :'ticketTypeID', :'tieCreatedUserID',
        :'tieIdSecondPurchaseID', :'ticketTypeID', :'tieIdUserID'
    ),
    'Should return one row per user with the seat purchase details'
);

-- Should return the latest completed purchase
select is(
    (
        select sp.event_purchase_id
        from event_seat_purchases(:'eventID'::uuid) sp
        where sp.user_id = :'latestCompletedUserID'::uuid
    ),
    :'latestCompletedReplacementPurchaseID'::uuid,
    'Should return the latest completed purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
