-- Tests leaving event enrollment states.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e090000-0000-0000-0000-000000000001'
\set eventApprovalPending '5e090000-0000-0000-0000-000000000002'
\set eventCategoryID '5e090000-0000-0000-0000-000000000004'
\set eventDisabledWaitlist '5e090000-0000-0000-0000-000000000006'
\set eventFull '5e090000-0000-0000-0000-000000000007'
\set eventOK '5e090000-0000-0000-0000-000000000009'
\set eventPaidTicketed '5e090000-0000-0000-0000-00000000000a'
\set eventPaidTicketedPurchaseID '5e090000-0000-0000-0000-00000000000b'
\set eventPaidTicketTypeID '5e090000-0000-0000-0000-00000000000c'
\set eventPast '5e090000-0000-0000-0000-00000000000d'
\set eventTicketed '5e090000-0000-0000-0000-000000000011'
\set eventTicketedDiscountCodeID '5e090000-0000-0000-0000-000000000012'
\set eventTicketedPurchaseID '5e090000-0000-0000-0000-000000000013'
\set eventTicketTypeID '5e090000-0000-0000-0000-000000000014'
\set eventTicketedPriceWindowID '5e090000-0000-0000-0000-000000000022'
\set eventUnlimited '5e090000-0000-0000-0000-000000000015'
\set eventWaitlist '5e090000-0000-0000-0000-000000000017'
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
select fx_event(:'eventDisabledWaitlist', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 2,
    'published', true
));
select fx_event(:'eventFull', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'name', 'Full',
    'published', true,
    'slug', 'full',
    'waitlist_enabled', true
));
select fx_event(:'eventPaidTicketed', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true
));
select fx_event(:'eventUnlimited', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Unlimited',
    'published', true,
    'slug', 'unlimited'
));
select fx_event(:'eventWaitlist', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'name', 'Waitlist',
    'published', true,
    'slug', 'waitlist',
    'waitlist_enabled', true
));

-- Event with scenario-specific state
select fx_event(:'eventTicketed', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
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

-- Events without a specialized ticket fixture use a default tier
select fx_event_ticket_type(gen_random_uuid(), e.event_id, jsonb_build_object(
    'seats_total', greatest(coalesce(e.capacity, 100), 1)
))
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current prices for ticket tiers without an explicit price fixture
select fx_event_ticket_price_window(
    gen_random_uuid(),
    ett.event_ticket_type_id,
    jsonb_build_object(
        'amount_minor',
        case when ett.event_id = :'eventPaidTicketed'::uuid then 1500 else 0 end
    )
)
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

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
    (:'eventDisabledWaitlist', :'user1ID', 'confirmed'),
    (:'eventDisabledWaitlist', :'user2ID', 'confirmed'),
    (:'eventPast', :'user1ID', 'confirmed'),
    (:'eventPaidTicketed', :'user3ID', 'confirmed'),
    (:'eventFull', :'user1ID', 'confirmed'),
    (:'eventUnlimited', :'user1ID', 'confirmed'),
    (:'eventTicketed', :'user1ID', 'confirmed');

-- Event Waitlists
insert into event_waitlist (created_at, event_id, event_ticket_type_id, user_id) values
    (current_timestamp, :'eventDisabledWaitlist', (select event_ticket_type_id from event_ticket_type where event_id = :'eventDisabledWaitlist' limit 1), :'user3ID'),
    (current_timestamp, :'eventFull', (select event_ticket_type_id from event_ticket_type where event_id = :'eventFull' limit 1), :'user2ID'),
    (current_timestamp + interval '1 minute', :'eventFull', (select event_ticket_type_id from event_ticket_type where event_id = :'eventFull' limit 1), :'user3ID'),
    (current_timestamp + interval '30 seconds', :'eventTicketed', :'eventTicketTypeID', :'user2ID'),
    (current_timestamp, :'eventUnlimited', (select event_ticket_type_id from event_ticket_type where event_id = :'eventUnlimited' limit 1), :'user2ID'),
    (current_timestamp + interval '1 minute', :'eventUnlimited', (select event_ticket_type_id from event_ticket_type where event_id = :'eventUnlimited' limit 1), :'user4ID'),
    (current_timestamp, :'eventWaitlist', (select event_ticket_type_id from event_ticket_type where event_id = :'eventWaitlist' limit 1), :'user2ID');

-- Event Invitation Requests
insert into event_invitation_request (event_id, event_ticket_type_id, user_id, status)
values (
    :'eventApprovalPending',
    (select event_ticket_type_id from event_ticket_type where event_id = :'eventApprovalPending' limit 1),
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

-- Every confirmed attendee owns capacity through a completed purchase
insert into event_purchase (
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
)
select
    0,
    null,
    0,
    ea.event_id,
    ett.event_ticket_type_id,
    'completed',
    ett.title,
    ea.user_id
from event_attendee ea
join lateral (
    select ett.event_ticket_type_id, ett.title
    from event_ticket_type ett
    where ett.event_id = ea.event_id
    order by ett."order", ett.event_ticket_type_id
    limit 1
) ett on true
where ea.status = 'confirmed'
and not exists (
    select 1
    from event_purchase ep
    where ep.event_id = ea.event_id
    and ep.user_id = ea.user_id
    and ep.status in (
        'completed',
        'refund-pending',
        'refund-recovery-pending',
        'refund-requested'
    )
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove an attendee from a normal event
select is(
    leave_event(:'communityID'::uuid, :'eventOK'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Removes attendee and returns attendee leave payload'
);

-- Should preserve inactive attendee history after leaving
select results_eq(
    format($$
        select
            attendance_canceled_at is not null,
            attendance_canceled_by_user_id,
            status
        from event_attendee
        where event_id = %L::uuid and user_id = %L::uuid
    $$, :'eventOK', :'user1ID'),
    format($$ values (true, %L::uuid, 'attendance-canceled'::text) $$, :'user1ID'),
    'Preserves inactive attendee history after leaving'
);

-- Should allow a user to leave the waitlist
select is(
    leave_event(:'communityID'::uuid, :'eventWaitlist'::uuid, :'user2ID'::uuid)::jsonb,
    '{"left_status":"waitlisted"}'::jsonb,
    'Removes waitlisted user and returns waitlisted leave payload'
);

-- Should remove waitlist row after leaving the waitlist
select ok(
    not exists(
        select 1
        from event_waitlist
        where event_id = :'eventWaitlist'::uuid and user_id = :'user2ID'::uuid
    ),
    'Deletes waitlist row after leaving the waitlist'
);

-- Should allow a user to leave a pending invitation request
select is(
    leave_event(:'communityID'::uuid, :'eventApprovalPending'::uuid, :'user4ID'::uuid)::jsonb,
    '{"left_status":"pending-approval"}'::jsonb,
    'Removes pending invitation request and returns pending-approval leave payload'
);

-- Should remove pending invitation request row after leaving
select ok(
    not exists(
        select 1
        from event_invitation_request
        where event_id = :'eventApprovalPending'::uuid and user_id = :'user4ID'::uuid
    ),
    'Deletes pending invitation request row after leaving'
);

-- Should promote the next waitlisted user when a confirmed attendee leaves a full event
select is(
    leave_event(:'communityID'::uuid, :'eventFull'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Leaves attendance after reconciling released capacity'
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

-- Should keep paid attendees and purchases unchanged after rejection
select is(
    (
        select jsonb_build_object(
            'attending', exists(
                select 1
                from event_attendee
                where event_id = :'eventPaidTicketed'::uuid
                and user_id = :'user3ID'::uuid
            ),
            'purchase_status', (
                select status
                from event_purchase
                where event_purchase_id = :'eventPaidTicketedPurchaseID'::uuid
            )
        )
    ),
    '{"attending": true, "purchase_status": "completed"}'::jsonb,
    'Should keep paid attendees and purchases unchanged after rejection'
);

-- Should create an offer for the oldest queued user
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
    'Preserves canceled attendance and offers the released seat to the queue head'
);

-- Should continue promoting existing waitlisted users after waitlist is disabled
select is(
    leave_event(:'communityID'::uuid, :'eventDisabledWaitlist'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Reconciles existing queued users even after waitlist is disabled'
);

-- Should promote the full remaining queue when an unlimited event loses an attendee
select is(
    leave_event(:'communityID'::uuid, :'eventUnlimited'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Reconciles all queued users when the synthesized tier has capacity'
);

-- Should reserve released ticket capacity for the FIFO queue
select is(
    leave_event(:'communityID'::uuid, :'eventTicketed'::uuid, :'user1ID'::uuid)::jsonb,
    '{"left_status":"attendee"}'::jsonb,
    'Should reconcile ticket capacity without returning promotion details'
);

-- Should convert the queued ticketed user into an admission offer
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
    'Should offer the released ticket to the queued user'
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

-- Should create offers for all queued users when the tier has capacity
select is(
    (
        select jsonb_build_object(
            'attendees', (
                select jsonb_agg(user_id order by user_id)
                from event_attendee
                where event_id = :'eventUnlimited'::uuid
            ),
            'offers', (
                select jsonb_agg(user_id order by user_id)
                from admission_offer
                where event_id = :'eventUnlimited'::uuid
                and status = 'pending'
            ),
            'waitlist', (
                select coalesce(jsonb_agg(user_id order by user_id), '[]'::jsonb)
                from event_waitlist
                where event_id = :'eventUnlimited'::uuid
            )
        )
    ),
    format(
        '{"attendees":["%s"],"offers":["%s","%s"],"waitlist":[]}',
        :'user1ID',
        :'user2ID',
        :'user4ID'
    )::jsonb,
    'Preserves canceled attendance and offers seats to the full queue'
);

-- Should reject past events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventPast', :'user1ID'
    ),
    'OCG01',
    'event not found or inactive',
    'Rejects leave requests for past events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
