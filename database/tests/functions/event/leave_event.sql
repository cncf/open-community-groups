-- Tests leaving event enrollment states.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(21);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e090000-0000-0000-0000-000000000001'
\set eventApprovalPending '5e090000-0000-0000-0000-000000000002'
\set eventCanceled '5e090000-0000-0000-0000-000000000003'
\set eventCategoryID '5e090000-0000-0000-0000-000000000004'
\set eventDeleted '5e090000-0000-0000-0000-000000000005'
\set eventDisabledWaitlist '5e090000-0000-0000-0000-000000000006'
\set eventFull '5e090000-0000-0000-0000-000000000007'
\set eventInactiveGroup '5e090000-0000-0000-0000-000000000008'
\set eventOK '5e090000-0000-0000-0000-000000000009'
\set eventPaidTicketed '5e090000-0000-0000-0000-00000000000a'
\set eventPaidTicketedPurchaseID '5e090000-0000-0000-0000-00000000000b'
\set eventPaidTicketTypeID '5e090000-0000-0000-0000-00000000000c'
\set eventPast '5e090000-0000-0000-0000-00000000000d'
\set eventStartedNoEnd '5e090000-0000-0000-0000-000000000010'
\set eventTicketed '5e090000-0000-0000-0000-000000000011'
\set eventTicketedDiscountCodeID '5e090000-0000-0000-0000-000000000012'
\set eventTicketedPurchaseID '5e090000-0000-0000-0000-000000000013'
\set eventTicketTypeID '5e090000-0000-0000-0000-000000000014'
\set eventTicketedPriceWindowID '5e090000-0000-0000-0000-000000000022'
\set eventUnlimited '5e090000-0000-0000-0000-000000000015'
\set eventUnpublished '5e090000-0000-0000-0000-000000000016'
\set eventWaitlist '5e090000-0000-0000-0000-000000000017'
\set groupCategoryID '5e090000-0000-0000-0000-000000000018'
\set groupID '5e090000-0000-0000-0000-000000000019'
\set inactiveGroupID '5e090000-0000-0000-0000-00000000001a'
\set user1ID '5e090000-0000-0000-0000-00000000001c'
\set user2ID '5e090000-0000-0000-0000-00000000001d'
\set user3ID '5e090000-0000-0000-0000-00000000001e'
\set user4ID '5e090000-0000-0000-0000-00000000001f'

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
    'test-community',
    'Test Community',
    'A test community',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (:'user1ID', 'user-1-hash', 'u1@test.com', true, 'u1'),
    (:'user2ID', 'user-2-hash', 'u2@test.com', true, 'u2'),
    (:'user3ID', 'user-3-hash', 'u3@test.com', true, 'u3'),
    (:'user4ID', 'user-4-hash', 'u4@test.com', true, 'u4');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug, active, deleted)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Active Group', 'active-group', true, false),
    (
        :'inactiveGroupID',
        :'communityID',
        :'groupCategoryID',
        'Inactive Group',
        'inactive-group',
        false,
        false
    );

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    attendee_approval_required,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
)
values
    (
        :'eventOK',
        'OK',
        'ok',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventApprovalPending',
        'Approval Pending',
        'approval-pending',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        true,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventCanceled',
        'Canceled',
        'canceled',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        true,
        false,
        null,
        null,
        1,
        true
    ),
    (
        :'eventDeleted',
        'Deleted',
        'deleted',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        false,
        true,
        null,
        null,
        null,
        false
    ),
    (
        :'eventInactiveGroup',
        'Inactive Group',
        'inactive-group',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'inactiveGroupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventUnpublished',
        'Unpublished',
        'unpublished',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        false,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventPast',
        'Past',
        'past',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        current_timestamp - interval '2 hours',
        current_timestamp - interval '1 hour',
        null,
        false
    ),
    (
        :'eventStartedNoEnd',
        'Started No End',
        'started-no-end',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        current_timestamp - interval '1 hour',
        null,
        null,
        false
    ),
    (
        :'eventDisabledWaitlist',
        'Disabled Waitlist',
        'disabled-waitlist',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        2,
        false
    ),
    (
        :'eventFull',
        'Full',
        'full',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        true
    ),
    (
        :'eventPaidTicketed',
        'Paid Ticketed',
        'paid-ticketed',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        false
    ),
    (
        :'eventUnlimited',
        'Unlimited',
        'unlimited',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        null,
        false
    ),
    (
        :'eventWaitlist',
        'Waitlist',
        'waitlist',
        'Test event',
        'UTC',
        :'eventCategoryID',
        'in-person',
        :'groupID',
        false,
        true,
        false,
        false,
        null,
        null,
        1,
        true
    );

-- Event
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    canceled,
    deleted,
    starts_at,
    ends_at,
    capacity,
    waitlist_enabled
) values (
    :'eventTicketed',
    'Ticketed',
    'ticketed',
    'd',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    false,
    null,
    null,
    1,
    false
);

-- Event Ticket Type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketTypeID',
    :'eventTicketed',
    1,
    1,
    'General admission'
);

-- Intrinsic-free price available to the next queued user
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    0,
    :'eventTicketedPriceWindowID',
    :'eventTicketTypeID'
);

-- Event Ticket Type
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'eventPaidTicketTypeID',
    :'eventPaidTicketed',
    1,
    1,
    'Paid admission'
);

-- Events without a specialized ticket fixture use a default tier
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
)
select
    e.event_id,
    gen_random_uuid(),
    1,
    greatest(coalesce(e.capacity, 100), 1),
    'General Admission'
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current prices for ticket tiers without an explicit price fixture
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
)
select
    case when ett.event_id = :'eventPaidTicketed'::uuid then 1500 else 0 end,
    gen_random_uuid(),
    ett.event_ticket_type_id
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
    (:'eventStartedNoEnd', :'user1ID', 'confirmed'),
    (:'eventFull', :'user1ID', 'confirmed'),
    (:'eventUnlimited', :'user1ID', 'confirmed'),
    (:'eventTicketed', :'user1ID', 'confirmed');

-- Event Waitlists
insert into event_waitlist (created_at, event_id, event_ticket_type_id, user_id) values
    (current_timestamp, :'eventCanceled', (select event_ticket_type_id from event_ticket_type where event_id = :'eventCanceled' limit 1), :'user4ID'),
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
    'event not found or inactive',
    'Rejects leave requests for past events'
);

-- Should reject started events without an end time
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventStartedNoEnd', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects started events without an end time for leave requests'
);

-- Should reject waitlist leave requests for canceled events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventCanceled', :'user4ID'
    ),
    'event not found or inactive',
    'Rejects waitlist leave requests for canceled events'
);

-- Should reject deleted events
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventDeleted', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for deleted events'
);

-- Should reject events from inactive groups
select throws_ok(
    format(
        'select leave_event(%L::uuid,%L::uuid,%L::uuid)',
        :'communityID', :'eventInactiveGroup', :'user1ID'
    ),
    'event not found or inactive',
    'Rejects leave requests for inactive-group events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
