-- Tests promoting event waitlist entries into admission offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3050000-0000-0000-0000-000000000001'
\set eventCategoryID 'f3050000-0000-0000-0000-000000000002'
\set externalGroupID 'f3050000-0000-0000-0000-00000000002b'
\set externalReadyEventID 'f3050000-0000-0000-0000-00000000002c'
\set externalReadyPriceWindowID 'f3050000-0000-0000-0000-00000000002d'
\set externalReadyTicketTypeID 'f3050000-0000-0000-0000-00000000002e'
\set externalReadyUserID 'f3050000-0000-0000-0000-00000000002f'
\set externalUnreadyEventID 'f3050000-0000-0000-0000-000000000030'
\set externalUnreadyPriceWindowID 'f3050000-0000-0000-0000-000000000031'
\set externalUnreadyTicketTypeID 'f3050000-0000-0000-0000-000000000032'
\set externalUnreadyUserID 'f3050000-0000-0000-0000-000000000033'
\set freeEventID 'f3050000-0000-0000-0000-000000000003'
\set freePriceWindowID 'f3050000-0000-0000-0000-000000000004'
\set freeTicketTypeID 'f3050000-0000-0000-0000-000000000005'
\set freeUserID 'f3050000-0000-0000-0000-000000000006'
\set fullEventID 'f3050000-0000-0000-0000-000000000007'
\set fullPriceWindowID 'f3050000-0000-0000-0000-000000000008'
\set fullPurchaseID 'f3050000-0000-0000-0000-000000000009'
\set fullTicketTypeID 'f3050000-0000-0000-0000-00000000000a'
\set fullUserID 'f3050000-0000-0000-0000-00000000000b'
\set fullWaitlistUserID 'f3050000-0000-0000-0000-00000000000c'
\set groupCategoryID 'f3050000-0000-0000-0000-00000000000d'
\set groupID 'f3050000-0000-0000-0000-00000000000e'
\set inactiveEventID 'f3050000-0000-0000-0000-00000000000f'
\set inactivePriceWindowID 'f3050000-0000-0000-0000-000000000010'
\set inactiveTicketTypeID 'f3050000-0000-0000-0000-000000000011'
\set inactiveUserID 'f3050000-0000-0000-0000-000000000012'
\set noPriceEventID 'f3050000-0000-0000-0000-000000000013'
\set noPriceTicketTypeID 'f3050000-0000-0000-0000-000000000014'
\set noPriceUserID 'f3050000-0000-0000-0000-000000000015'
\set paidBlockedEventID 'f3050000-0000-0000-0000-000000000016'
\set paidBlockedPriceWindowID 'f3050000-0000-0000-0000-000000000017'
\set paidBlockedTicketTypeID 'f3050000-0000-0000-0000-000000000018'
\set paidBlockedUserID 'f3050000-0000-0000-0000-000000000019'
\set paidReadyEventID 'f3050000-0000-0000-0000-00000000001a'
\set paidReadyPriceWindowID 'f3050000-0000-0000-0000-00000000001b'
\set paidReadyTicketTypeID 'f3050000-0000-0000-0000-00000000001c'
\set paidReadyUserID 'f3050000-0000-0000-0000-00000000001d'
\set pastEventID 'f3050000-0000-0000-0000-00000000001e'
\set pastPriceWindowID 'f3050000-0000-0000-0000-00000000001f'
\set pastTicketTypeID 'f3050000-0000-0000-0000-000000000020'
\set pastUserID 'f3050000-0000-0000-0000-000000000021'
\set privatePriceWindowID 'f3050000-0000-0000-0000-000000000022'
\set privateTicketTypeID 'f3050000-0000-0000-0000-000000000023'
\set privateUserID 'f3050000-0000-0000-0000-000000000024'
\set scopedBlockedTicketTypeID 'f3050000-0000-0000-0000-000000000025'
\set scopedBlockedUserID 'f3050000-0000-0000-0000-000000000026'
\set scopedEventID 'f3050000-0000-0000-0000-000000000027'
\set scopedPriceWindowID 'f3050000-0000-0000-0000-000000000028'
\set scopedTicketTypeID 'f3050000-0000-0000-0000-000000000029'
\set scopedUserID 'f3050000-0000-0000-0000-00000000002a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'externalReadyUserID');
select fx_user(:'externalUnreadyUserID');
select fx_user(:'freeUserID');
select fx_user(:'fullUserID');
select fx_user(:'fullWaitlistUserID');
select fx_user(:'inactiveUserID');
select fx_user(:'noPriceUserID');
select fx_user(:'paidBlockedUserID');
select fx_user(:'paidReadyUserID');
select fx_user(:'pastUserID');
select fx_user(:'privateUserID');
select fx_user(:'scopedBlockedUserID');
select fx_user(:'scopedUserID');

-- Operator allowlist that makes the external group's country eligible
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Group with the matching Stripe recipient used by paid promotions
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Promote Waitlist Group',
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_promote_waitlist',
        'seller_display_name', 'Promote Waitlist Seller'
    )
));

-- Allowlisted group with external payments ready
select fx_group(:'externalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co',
    'name', 'Promote External Group'
));

-- External-ready paid event promoted without a Stripe provider
select fx_event(:'externalReadyEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/ready-queue',
    'name', 'Promote External Ready Event',
    'payment_currency_code', 'KRW',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- External-marked paid event on a Stripe-ready group that is not externally eligible
select fx_event(:'externalUnreadyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/unready-queue',
    'name', 'Promote External Unready Event',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Free event whose registration close bounds the offer expiry
select fx_event(:'freeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Free Event',
    'registration_ends_at', current_timestamp + interval '12 hours',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Full event with no remaining ticket capacity
select fx_event(:'fullEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Full Event',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Event with inactive and invitation-only ticket tiers
select fx_event(:'inactiveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Inactive Event',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Event whose FIFO head has no current price window
select fx_event(:'noPriceEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote No Price Event',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Paid event blocked while no server provider is configured
select fx_event(:'paidBlockedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Paid Blocked Event',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Paid event promoted when the configured provider matches the group recipient
select fx_event(:'paidReadyEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Paid Ready Event',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- Event whose start time would make a promoted offer expire immediately
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Past Event',
    'starts_at', current_timestamp - interval '1 hour',
    'waitlist_enabled', true
));

-- Event with two queues used to prove scoped ticket-tier promotion
select fx_event(:'scopedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Promote Scoped Event',
    'starts_at', current_timestamp + interval '2 days',
    'waitlist_enabled', true
));

-- External-ready paid ticket tier
select fx_event_ticket_type(:'externalReadyTicketTypeID', :'externalReadyEventID', jsonb_build_object('seats_total', 1));

-- External-marked unready paid ticket tier
select fx_event_ticket_type(:'externalUnreadyTicketTypeID', :'externalUnreadyEventID', jsonb_build_object('seats_total', 1));

-- Free ticket tier with one queued seat available
select fx_event_ticket_type(:'freeTicketTypeID', :'freeEventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'Free promoted admission'
));

-- Full ticket tier whose only seat is already allocated
select fx_event_ticket_type(:'fullTicketTypeID', :'fullEventID', jsonb_build_object('seats_total', 1));

-- Inactive ticket tier skipped by promotion
select fx_event_ticket_type(:'inactiveTicketTypeID', :'inactiveEventID', jsonb_build_object(
    'active', false,
    'seats_total', 1
));

-- No-price ticket tier that keeps the FIFO head queued
select fx_event_ticket_type(:'noPriceTicketTypeID', :'noPriceEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier blocked without a configured provider
select fx_event_ticket_type(:'paidBlockedTicketTypeID', :'paidBlockedEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier promoted with matching Stripe readiness
select fx_event_ticket_type(:'paidReadyTicketTypeID', :'paidReadyEventID', jsonb_build_object('seats_total', 1));

-- Past-start ticket tier whose offer window is already closed
select fx_event_ticket_type(:'pastTicketTypeID', :'pastEventID', jsonb_build_object('seats_total', 1));

-- Invitation-only ticket tier skipped by promotion
select fx_event_ticket_type(:'privateTicketTypeID', :'inactiveEventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 1
));

-- Scoped ticket tier selected for promotion
select fx_event_ticket_type(:'scopedTicketTypeID', :'scopedEventID', jsonb_build_object('seats_total', 1));

-- Unscoped ticket tier left queued by scoped promotion
select fx_event_ticket_type(:'scopedBlockedTicketTypeID', :'scopedEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 1
));

-- Paid current price collected through external payments
select fx_event_ticket_price_window(:'externalReadyPriceWindowID', :'externalReadyTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Paid current price blocked while external payments are not ready
select fx_event_ticket_price_window(:'externalUnreadyPriceWindowID', :'externalUnreadyTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Free current price used by the free promotion
select fx_event_ticket_price_window(:'freePriceWindowID', :'freeTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Free current price used by the full-capacity scenario
select fx_event_ticket_price_window(:'fullPriceWindowID', :'fullTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Free current price used by the inactive-tier scenario
select fx_event_ticket_price_window(:'inactivePriceWindowID', :'inactiveTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Paid current price blocked without server payment configuration
select fx_event_ticket_price_window(:'paidBlockedPriceWindowID', :'paidBlockedTicketTypeID', jsonb_build_object('amount_minor', 1000));

-- Paid current price promoted with matching Stripe readiness
select fx_event_ticket_price_window(:'paidReadyPriceWindowID', :'paidReadyTicketTypeID', jsonb_build_object('amount_minor', 1000));

-- Free current price used by the past-start scenario
select fx_event_ticket_price_window(:'pastPriceWindowID', :'pastTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Free current price used by the invitation-only scenario
select fx_event_ticket_price_window(:'privatePriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Free current price used by the scoped promotion scenario
select fx_event_ticket_price_window(:'scopedPriceWindowID', :'scopedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Completed purchase that fills the full ticket tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'fullEventID',
    :'fullPurchaseID',
    :'fullTicketTypeID',
    'completed',
    'Full admission',
    :'fullUserID'
);

-- FIFO waitlist entries for each promotion branch
insert into event_waitlist (
    created_at,
    event_id,
    event_ticket_type_id,
    user_id
) values (
    '2024-01-01 00:00:00+00',
    :'externalReadyEventID',
    :'externalReadyTicketTypeID',
    :'externalReadyUserID'
), (
    '2024-01-01 00:00:00+00',
    :'externalUnreadyEventID',
    :'externalUnreadyTicketTypeID',
    :'externalUnreadyUserID'
), (
    '2024-01-01 00:00:00+00',
    :'freeEventID',
    :'freeTicketTypeID',
    :'freeUserID'
), (
    '2024-01-01 00:00:00+00',
    :'fullEventID',
    :'fullTicketTypeID',
    :'fullWaitlistUserID'
), (
    '2024-01-01 00:00:00+00',
    :'inactiveEventID',
    :'inactiveTicketTypeID',
    :'inactiveUserID'
), (
    '2024-01-02 00:00:00+00',
    :'inactiveEventID',
    :'privateTicketTypeID',
    :'privateUserID'
), (
    '2024-01-01 00:00:00+00',
    :'noPriceEventID',
    :'noPriceTicketTypeID',
    :'noPriceUserID'
), (
    '2024-01-01 00:00:00+00',
    :'paidBlockedEventID',
    :'paidBlockedTicketTypeID',
    :'paidBlockedUserID'
), (
    '2024-01-01 00:00:00+00',
    :'paidReadyEventID',
    :'paidReadyTicketTypeID',
    :'paidReadyUserID'
), (
    '2024-01-01 00:00:00+00',
    :'pastEventID',
    :'pastTicketTypeID',
    :'pastUserID'
), (
    '2024-01-01 00:00:00+00',
    :'scopedEventID',
    :'scopedTicketTypeID',
    :'scopedUserID'
), (
    '2024-01-02 00:00:00+00',
    :'scopedEventID',
    :'scopedBlockedTicketTypeID',
    :'scopedBlockedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep paid queue heads while server payments are unavailable
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'paidBlockedEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should keep paid queue heads while server payments are unavailable'
);

-- Should keep queue heads whose offer would expire immediately
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'pastEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should keep queue heads whose offer would expire immediately'
);

-- Should leave an external-marked unready queue idle even with Stripe configured
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'externalUnreadyEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        'stripe',
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should leave an external-marked unready queue idle even with Stripe configured'
);

-- Should leave full ticket tiers queued
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'fullEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should leave full ticket tiers queued'
);

-- Should leave inactive and invitation-only tiers queued
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'inactiveEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should leave inactive and invitation-only tiers queued'
);

-- Should leave no-price queue heads in place
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'noPriceEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[]::uuid[],
    'Should leave no-price queue heads in place'
);

-- Should limit promotion to the scoped ticket tier
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'scopedEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        :'scopedTicketTypeID',
        null,
        '{}'::jsonb
    ),
    array[:'scopedUserID'::uuid],
    'Should limit promotion to the scoped ticket tier'
);

-- Should promote an external-ready paid queue without a Stripe provider
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'externalReadyEventID'),
        (select g from "group" g where g.group_id = :'externalGroupID'),
        null,
        null,
        '{}'::jsonb
    ),
    array[:'externalReadyUserID'::uuid],
    'Should promote an external-ready paid queue without a Stripe provider'
);

-- Should promote free public queue heads into pending offers
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'freeEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        null,
        jsonb_build_object('primary_color', '#2563eb')
    ),
    array[:'freeUserID'::uuid],
    'Should promote free public queue heads into pending offers'
);

-- Should promote paid queue heads when Stripe readiness matches
select is(
    promote_event_waitlist_entries(
        (select e from event e where e.event_id = :'paidReadyEventID'),
        (select g from "group" g where g.group_id = :'groupID'),
        null,
        'stripe',
        '{}'::jsonb
    ),
    array[:'paidReadyUserID'::uuid],
    'Should promote paid queue heads when Stripe readiness matches'
);

-- Should audit every promoted waitlist offer as a system action
select set_eq(
    format(
        $$
            select
                al.actor_user_id,
                al.community_id,
                al.details,
                al.event_id,
                al.group_id,
                al.resource_id,
                al.resource_type
            from audit_log al
            where al.action = 'event_ticket_waitlist_offer_created'
            and al.group_id in (%L::uuid, %L::uuid)
        $$,
        :'externalGroupID',
        :'groupID'
    ),
    format(
        $$
            select
                null::uuid as actor_user_id,
                %L::uuid as community_id,
                jsonb_build_object(
                    'admission_offer_id', ao.admission_offer_id,
                    'event_ticket_type_id', ao.event_ticket_type_id,
                    'user_id', ao.user_id
                ) as details,
                ao.event_id,
                e.group_id,
                ao.admission_offer_id as resource_id,
                'admission_offer'::text as resource_type
            from admission_offer ao
            join event e using (event_id)
            where e.group_id in (%L::uuid, %L::uuid)
        $$,
        :'communityID',
        :'externalGroupID',
        :'groupID'
    ),
    'Should audit every promoted waitlist offer as a system action'
);

-- Should notify every promoted waitlist user
select set_eq(
    format(
        $$
            select n.user_id
            from notification n
            where n.kind = 'event-ticket-waitlist-offer'
            and n.user_id in (%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)
        $$,
        :'externalReadyUserID',
        :'freeUserID',
        :'paidReadyUserID',
        :'scopedBlockedUserID',
        :'scopedUserID'
    ),
    format(
        $$ values (%L::uuid), (%L::uuid), (%L::uuid), (%L::uuid) $$,
        :'externalReadyUserID',
        :'freeUserID',
        :'paidReadyUserID',
        :'scopedUserID'
    ),
    'Should notify every promoted waitlist user'
);

-- Should persist promoted waitlist offers with expiry capped by 24 hours or registration close
select set_eq(
    format(
        $$
            select ao.event_id, ao.user_id, ao.status, ao.expires_at
            from admission_offer ao
            join event e using (event_id)
            where e.group_id in (%L::uuid, %L::uuid)
        $$,
        :'externalGroupID',
        :'groupID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid, 'pending'::text, current_timestamp + interval '24 hours'),
            (%L::uuid, %L::uuid, 'pending'::text, current_timestamp + interval '12 hours'),
            (%L::uuid, %L::uuid, 'pending'::text, current_timestamp + interval '24 hours'),
            (%L::uuid, %L::uuid, 'pending'::text, current_timestamp + interval '24 hours')
        $$,
        :'externalReadyEventID',
        :'externalReadyUserID',
        :'freeEventID',
        :'freeUserID',
        :'paidReadyEventID',
        :'paidReadyUserID',
        :'scopedEventID',
        :'scopedUserID'
    ),
    'Should persist promoted waitlist offers with expiry capped by 24 hours or registration close'
);

-- Should retain unpromoted queue heads
select set_eq(
    format(
        $$
            select ew.event_id, ew.user_id
            from event_waitlist ew
            join event e using (event_id)
            where e.group_id in (%L::uuid, %L::uuid)
        $$,
        :'externalGroupID',
        :'groupID'
    ),
    format(
        $$ values
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid),
            (%L::uuid, %L::uuid)
        $$,
        :'externalUnreadyEventID',
        :'externalUnreadyUserID',
        :'fullEventID',
        :'fullWaitlistUserID',
        :'inactiveEventID',
        :'inactiveUserID',
        :'inactiveEventID',
        :'privateUserID',
        :'noPriceEventID',
        :'noPriceUserID',
        :'paidBlockedEventID',
        :'paidBlockedUserID',
        :'pastEventID',
        :'pastUserID',
        :'scopedEventID',
        :'scopedBlockedUserID'
    ),
    'Should retain unpromoted queue heads'
);

-- Should write notification context for promoted waitlist offers
select is(
    (
        select ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-ticket-waitlist-offer'
        and n.user_id = :'freeUserID'
    ),
    (
        select jsonb_build_object(
            'admission_offer_id', ao.admission_offer_id,
            'amount_minor', 0,
            'currency_code', null,
            'dashboard_url', format('/dashboard/user?tab=invitations#event-offer-%s', ao.admission_offer_id),
            'event_id', :'freeEventID',
            'event_name', 'Promote Free Event',
            'event_ticket_type_id', :'freeTicketTypeID',
            'expires_at', epoch_seconds(current_timestamp + interval '12 hours'),
            'group_name', 'Promote Waitlist Group',
            'is_simple_rsvp', true,
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'Free promoted admission',
            'timezone', 'UTC',
            'user_id', :'freeUserID'
        )
        from admission_offer ao
        where ao.event_id = :'freeEventID'
        and ao.user_id = :'freeUserID'
    ),
    'Should write notification context for promoted waitlist offers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
