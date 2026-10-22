-- Tests leaving event enrollment states.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e090000-0000-0000-0000-000000000001'
\set eventApprovalPending '5e090000-0000-0000-0000-000000000002'
\set eventApprovalPendingPriceWindowID '5e090000-0000-0000-0000-000000000023'
\set eventApprovalPendingTicketTypeID '5e090000-0000-0000-0000-000000000024'
\set eventCategoryID '5e090000-0000-0000-0000-000000000004'
\set eventFull '5e090000-0000-0000-0000-000000000007'
\set eventFullPriceWindowID '5e090000-0000-0000-0000-000000000025'
\set eventFullPurchaseID '5e090000-0000-0000-0000-000000000026'
\set eventFullTicketTypeID '5e090000-0000-0000-0000-000000000027'
\set eventOK '5e090000-0000-0000-0000-000000000009'
\set eventOKPriceWindowID '5e090000-0000-0000-0000-000000000028'
\set eventOKPurchaseID '5e090000-0000-0000-0000-000000000029'
\set eventOKTicketTypeID '5e090000-0000-0000-0000-00000000002a'
\set eventPaidPriceWindowID '5e090000-0000-0000-0000-00000000002b'
\set eventPaidTicketed '5e090000-0000-0000-0000-00000000000a'
\set eventPaidTicketedPurchaseID '5e090000-0000-0000-0000-00000000000b'
\set eventPaidTicketTypeID '5e090000-0000-0000-0000-00000000000c'
\set eventPast '5e090000-0000-0000-0000-00000000000d'
\set eventPastPriceWindowID '5e090000-0000-0000-0000-00000000002c'
\set eventPastPurchaseID '5e090000-0000-0000-0000-00000000002d'
\set eventPastTicketTypeID '5e090000-0000-0000-0000-00000000002e'
\set eventTicketed '5e090000-0000-0000-0000-000000000011'
\set eventTicketedDiscountCodeID '5e090000-0000-0000-0000-000000000012'
\set eventTicketedPriceWindowID '5e090000-0000-0000-0000-000000000022'
\set eventTicketedPurchaseID '5e090000-0000-0000-0000-000000000013'
\set eventTicketTypeID '5e090000-0000-0000-0000-000000000014'
\set eventWaitlist '5e090000-0000-0000-0000-000000000017'
\set eventWaitlistPriceWindowID '5e090000-0000-0000-0000-00000000002f'
\set eventWaitlistTicketTypeID '5e090000-0000-0000-0000-000000000030'
\set groupCategoryID '5e090000-0000-0000-0000-000000000018'
\set groupID '5e090000-0000-0000-0000-000000000019'
\set user1ID '5e090000-0000-0000-0000-00000000001c'
\set user2ID '5e090000-0000-0000-0000-00000000001d'
\set user3ID '5e090000-0000-0000-0000-00000000001e'
\set user4ID '5e090000-0000-0000-0000-00000000001f'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'user1ID');
select fx_user(:'user2ID');
select fx_user(:'user3ID');
select fx_user(:'user4ID');

-- Group with scenario-specific state
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('slug', 'active-group'));

-- Events with scenario-specific state
select fx_event(:'eventOK', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'OK',
    'published', true,
    'slug', 'ok'
));
select fx_event(:'eventApprovalPending', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));
select fx_event(:'eventPast', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 hour',
    'name', 'Past',
    'published', true,
    'slug', 'past',
    'starts_at', current_timestamp - interval '2 hours'
));
select fx_event(:'eventFull', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Full',
    'published', true,
    'slug', 'full',
    'waitlist_enabled', true
));
select fx_event(:'eventPaidTicketed', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));
select fx_event(:'eventWaitlist', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Waitlist',
    'published', true,
    'slug', 'waitlist',
    'waitlist_enabled', true
));

-- Event with scenario-specific state
select fx_event(:'eventTicketed', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Ticketed',
    'payment_currency_code', 'USD',
    'published', true,
    'slug', 'ticketed'
));

-- Ticket tier for direct paid checkout
select fx_event_ticket_type(:'eventTicketTypeID', :'eventTicketed', jsonb_build_object('seats_total', 1));

-- Intrinsic-free price available to the next queued user
select fx_event_ticket_price_window(:'eventTicketedPriceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Paid ticket tier used to test refunded purchase handling
select fx_event_ticket_type(:'eventPaidTicketTypeID', :'eventPaidTicketed', jsonb_build_object('seats_total', 1));

-- Positive price that makes the paid attendee request a refund instead of leaving
select fx_event_ticket_price_window(:'eventPaidPriceWindowID', :'eventPaidTicketTypeID', jsonb_build_object('amount_minor', 1500));

-- Single-seat tiers for the full and waitlist events
select fx_event_ticket_type(:'eventFullTicketTypeID', :'eventFull', jsonb_build_object('seats_total', 1, 'title', 'General Admission'));
select fx_event_ticket_type(:'eventWaitlistTicketTypeID', :'eventWaitlist', jsonb_build_object('seats_total', 1));

-- Ten-seat tiers, leaving a free seat for each attendance scenario
select fx_event_ticket_type(:'eventApprovalPendingTicketTypeID', :'eventApprovalPending', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'eventOKTicketTypeID', :'eventOK', jsonb_build_object('seats_total', 10, 'title', 'General Admission'));
select fx_event_ticket_type(:'eventPastTicketTypeID', :'eventPast', jsonb_build_object('seats_total', 10, 'title', 'General Admission'));

-- Current free prices for the RSVP tiers
select fx_event_ticket_price_window(:'eventApprovalPendingPriceWindowID', :'eventApprovalPendingTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventFullPriceWindowID', :'eventFullTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventOKPriceWindowID', :'eventOKTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventPastPriceWindowID', :'eventPastTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventWaitlistPriceWindowID', :'eventWaitlistTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Event Discount Code
insert into event_discount_code (
    event_discount_code_id,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'eventTicketedDiscountCodeID',
    1,
    0,
    true,
    'FREEPASS',
    :'eventTicketed',
    'fixed_amount',
    'Free pass'
);

-- Event Attendees
insert into event_attendee (event_id, user_id, status) values
    (:'eventOK', :'user1ID', 'confirmed'),
    (:'eventPast', :'user1ID', 'confirmed'),
    (:'eventPaidTicketed', :'user3ID', 'confirmed'),
    (:'eventFull', :'user1ID', 'confirmed'),
    (:'eventTicketed', :'user1ID', 'confirmed');

-- Event Waitlists
insert into event_waitlist (created_at, event_id, event_ticket_type_id, user_id) values
    (current_timestamp, :'eventFull', :'eventFullTicketTypeID', :'user2ID'),
    (current_timestamp + interval '1 minute', :'eventFull', :'eventFullTicketTypeID', :'user3ID'),
    (current_timestamp + interval '30 seconds', :'eventTicketed', :'eventTicketTypeID', :'user2ID'),
    (current_timestamp, :'eventWaitlist', :'eventWaitlistTicketTypeID', :'user2ID');

-- Event Invitation Requests
insert into event_invitation_request (event_id, event_ticket_type_id, user_id, status)
values (
    :'eventApprovalPending',
    :'eventApprovalPendingTicketTypeID',
    :'user4ID',
    'pending'
);

-- Event Purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    :'eventTicketedPurchaseID',
    0,
    'USD',
    'FREEPASS',
    :'eventTicketedDiscountCodeID',
    :'eventTicketed',
    :'eventTicketTypeID',
    'completed',
    'General admission',
    :'user1ID'
);

-- Completed direct-charge purchase for the paid event
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    status,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'eventPaidTicketedPurchaseID',
    1500,
    'direct-charge',
    'acct_leave_event_test',
    'USD',
    :'eventPaidTicketed',
    :'eventPaidTicketTypeID',
    0,
    'stripe',
    'ch_leave_event_paid',
    'cs_leave_event_paid',
    'acct_leave_event_test',
    'pi_leave_event_paid',
    1500,
    '{}'::jsonb,
    'completed',
    1500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'Paid admission',
    :'user3ID',
    '{}'::jsonb
);

-- Completed free purchases that own the seats of the RSVP attendees
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values
    (:'eventFullPurchaseID', 0, 0, :'eventFull', :'eventFullTicketTypeID', 'completed', 'General Admission', :'user1ID'),
    (:'eventOKPurchaseID', 0, 0, :'eventOK', :'eventOKTicketTypeID', 'completed', 'General Admission', :'user1ID'),
    (:'eventPastPurchaseID', 0, 0, :'eventPast', :'eventPastTicketTypeID', 'completed', 'General Admission', :'user1ID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove an attendee from a normal event
select is(
    leave_event(:'communityID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Should remove an attendee from a normal event'
);

-- Should preserve inactive attendee history after leaving
select results_eq(
    format($$
        select
            attendance_canceled_at = current_timestamp,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid and user_id = %L::uuid
    $$, :'eventOK', :'user1ID'),
    format($$ values (true, %L::uuid, 'attendance-canceled'::text) $$, :'user1ID'),
    'Should preserve inactive attendee history after leaving'
);

-- Should allow a user to leave the waitlist
select is(
    leave_event(:'communityID'::uuid, :'eventWaitlist'::uuid, :'user2ID'::uuid)::jsonb,
    '{"left_status":"waitlisted"}'::jsonb,
    'Should allow a user to leave the waitlist'
);

-- Should remove waitlist row after leaving the waitlist
select ok(
    not exists(
        select 1
        from event_waitlist
        where event_id = :'eventWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Should remove waitlist row after leaving the waitlist'
);

-- Should allow a user to leave a pending invitation request
select is(
    leave_event(:'communityID'::uuid, :'eventApprovalPending'::uuid, :'user4ID'::uuid)::jsonb,
    '{"left_status":"pending-approval"}'::jsonb,
    'Should allow a user to leave a pending invitation request'
);

-- Should remove pending invitation request row after leaving
select ok(
    not exists(
        select 1
        from event_invitation_request
        where event_id = :'eventApprovalPending'::uuid and user_id = :'user4ID'::uuid
    ),
    'Should remove pending invitation request row after leaving'
);

-- Should release the seat when a confirmed attendee leaves a full event
select is(
    leave_event(:'communityID'::uuid, :'eventFull'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Should release the seat when a confirmed attendee leaves a full event'
);

-- Should offer the released seat to the oldest queued user
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventFull'::uuid
            ),
            'offers', (
                select jsonb_agg(user_id order by user_id)
                from admission_offer
                where event_id = :'eventFull'::uuid
                and status = 'pending'
            ),
            'waitlist', (
                select jsonb_agg(user_id order by user_id)
                from event_waitlist
                where event_id = :'eventFull'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"offers":["%s"],"waitlist":["%s"]}',
        :'user1ID',
        :'user2ID',
        :'user3ID'
    )::jsonb,
    'Should offer the released seat to the oldest queued user'
);

-- Should release the ticket when a free ticketed attendee leaves
select is(
    leave_event(:'communityID'::uuid, :'eventTicketed'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Should release the ticket when a free ticketed attendee leaves'
);

-- Should refund the free purchase and offer the released ticket to the queued user
select is(
    (
        select jsonb_build_object(
            'offer', (
                select jsonb_build_array(status, user_id)
                from admission_offer
                where event_id = :'eventTicketed'::uuid
                and event_ticket_type_id = :'eventTicketTypeID'::uuid
            ),
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'eventTicketedPurchaseID'::uuid
            ),
            'waitlist_count', (
                select count(*)
                from event_waitlist
                where event_id = :'eventTicketed'::uuid
            )
        )
    ),
    format(
        '{"offer":["pending","%s"],"purchase_status":"refunded","waitlist_count":0}',
        :'user2ID'
    )::jsonb,
    'Should refund the free purchase and offer the released ticket to the queued user'
);

-- Should restore the discount code remaining uses when a free ticketed attendee leaves
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'eventTicketedDiscountCodeID'::uuid
    ),
    1,
    'Should restore the discount code remaining uses when a free ticketed attendee leaves'
);

-- Should reject paid attendees trying to leave a ticketed event
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPaidTicketed', :'user3ID'
    ),
    'OCG01',
    'paid attendees must request a refund instead of leaving the event',
    'Should reject paid attendees trying to leave a ticketed event'
);

-- Should reject past events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject past events'
);

-- Should reject users who are not attending or waitlisted
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventOK', :'user2ID'
    ),
    'OCG01',
    'user is not attending or waitlisted for this event',
    'Should reject users who are not attending or waitlisted'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
