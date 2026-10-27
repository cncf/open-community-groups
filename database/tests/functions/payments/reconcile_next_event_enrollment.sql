-- Tests claiming the next event that requires enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set closedRegistrationEventID '5e050000-0000-0000-0000-000000000021'
\set closedRegistrationPriceWindowID '5e050000-0000-0000-0000-000000000022'
\set closedRegistrationRecipientID '5e050000-0000-0000-0000-000000000023'
\set closedRegistrationTicketTypeID '5e050000-0000-0000-0000-000000000024'
\set communityID '5e050000-0000-0000-0000-000000000001'
\set dueOfferID '5e050000-0000-0000-0000-000000000002'
\set eventCategoryID '5e050000-0000-0000-0000-000000000003'
\set eventID '5e050000-0000-0000-0000-000000000004'
\set expiredHoldEventID '5e050000-0000-0000-0000-00000000002b'
\set expiredHoldPurchaseID '5e050000-0000-0000-0000-00000000002c'
\set expiredHoldRecipientID '5e050000-0000-0000-0000-00000000002d'
\set expiredHoldTicketTypeID '5e050000-0000-0000-0000-00000000002e'
\set externalGroupID '5e050000-0000-0000-0000-000000000011'
\set externalQueueEventID '5e050000-0000-0000-0000-000000000012'
\set externalQueuePriceWindowID '5e050000-0000-0000-0000-000000000019'
\set externalQueueRecipientID '5e050000-0000-0000-0000-000000000013'
\set externalQueueTicketTypeID '5e050000-0000-0000-0000-000000000014'
\set externalReminderEventID '5e050000-0000-0000-0000-000000000015'
\set externalReminderPriceWindowID '5e050000-0000-0000-0000-00000000001a'
\set externalReminderPurchaseID '5e050000-0000-0000-0000-000000000016'
\set externalReminderRecipientID '5e050000-0000-0000-0000-000000000017'
\set externalReminderTicketTypeID '5e050000-0000-0000-0000-000000000018'
\set futureOfferID '5e050000-0000-0000-0000-000000000005'
\set futureRecipientID '5e050000-0000-0000-0000-000000000006'
\set groupCategoryID '5e050000-0000-0000-0000-000000000007'
\set groupID '5e050000-0000-0000-0000-000000000008'
\set incompleteVenueEventID '5e050000-0000-0000-0000-00000000001d'
\set incompleteVenuePriceWindowID '5e050000-0000-0000-0000-00000000001e'
\set incompleteVenueRecipientID '5e050000-0000-0000-0000-00000000001f'
\set incompleteVenueTicketTypeID '5e050000-0000-0000-0000-000000000020'
\set notDueEventID '5e050000-0000-0000-0000-000000000000'
\set notDueOfferID '5e050000-0000-0000-0000-000000000025'
\set notDueOfferRecipientID '5e050000-0000-0000-0000-000000000026'
\set notDuePriceWindowID '5e050000-0000-0000-0000-000000000027'
\set notDuePurchaseID '5e050000-0000-0000-0000-000000000028'
\set notDuePurchaseRecipientID '5e050000-0000-0000-0000-000000000029'
\set notDueTicketTypeID '5e050000-0000-0000-0000-00000000002a'
\set priceWindowID '5e050000-0000-0000-0000-00000000000b'
\set queueRecipientID '5e050000-0000-0000-0000-00000000000c'
\set recipientID '5e050000-0000-0000-0000-000000000009'
\set rsvpDueOfferID '5e050000-0000-0000-0000-00000000000d'
\set rsvpEventID '5e050000-0000-0000-0000-00000000000e'
\set rsvpPriceWindowID '5e050000-0000-0000-0000-00000000001b'
\set rsvpQueueRecipientID '5e050000-0000-0000-0000-00000000000f'
\set rsvpRecipientID '5e050000-0000-0000-0000-000000000010'
\set rsvpTicketTypeID '5e050000-0000-0000-0000-00000000001c'
\set ticketTypeID '5e050000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning every reconciliation scenario
select fx_community(:'communityID');

-- Operator allowlist used by external-ready worker claims
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Queue head kept idle while registration is closed
select fx_user(:'closedRegistrationRecipientID');

-- Holder of the expired direct-charge hold
select fx_user(:'expiredHoldRecipientID');

-- Queue head promoted on the external-ready paid event
select fx_user(:'externalQueueRecipientID');

-- Holder of the reminder-due external hold
select fx_user(:'externalReminderRecipientID');

-- Recipient of the future admission offer
select fx_user(:'futureRecipientID', jsonb_build_object('username', 'future'));

-- Queue head kept idle while the venue is incomplete
select fx_user(:'incompleteVenueRecipientID');

-- Recipient of the admission offer that is not due
select fx_user(:'notDueOfferRecipientID');

-- Holder of the direct-charge hold that is not due
select fx_user(:'notDuePurchaseRecipientID');

-- Paid queue head blocked until the payment provider becomes available
select fx_user(:'queueRecipientID', jsonb_build_object('username', 'queue'));

-- Recipient of the due admission offer
select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-next-event-enrollment'));

-- Free RSVP queue head promoted by background reconciliation
select fx_user(:'rsvpQueueRecipientID');

-- Recipient of the due RSVP admission offer
select fx_user(:'rsvpRecipientID');

-- Event category shared by every reconciliation event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category shared by every reconciliation group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group with a configured recipient for paid queue recovery
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_reconciliation_worker", "seller_display_name": "Worker Fiscal Sponsor"}'::jsonb));

-- Allowlisted group with external payments enabled for worker claims
select fx_group(:'externalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Stripe-ready published event with one due and one future admission offer
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'manual_tax_rate_ids', '{}'::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic',
    'venue_address', '1 Worker Way',
    'venue_city', 'Worker City',
    'venue_country_code', 'US',
    'venue_name', 'Worker Hall',
    'venue_zip_code', '12345'
));

-- RSVP event with a due offer and one waiting recipient
select fx_event(:'rsvpEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- External-ready paid event claimed after Stripe work is exhausted
select fx_event(:'externalQueueEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/worker-queue',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Event hosting a reminder-due external pending hold
select fx_event(:'externalReminderEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/worker-reminder',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Event whose only pending work is an expired direct-charge hold
select fx_event(:'expiredHoldEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Stripe-paid event whose venue lacks a zip code
select fx_event(:'incompleteVenueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'manual_tax_rate_ids', '{}'::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'tax_calculation_mode', 'automatic',
    'venue_address', '1 Partial Way',
    'venue_city', 'Partial City',
    'venue_country_code', 'US',
    'venue_name', 'Partial Hall',
    'waitlist_enabled', true
));

-- Published future event whose registration already closed
select fx_event(:'closedRegistrationEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_ends_at', current_timestamp - interval '1 hour',
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Lowest-id event whose reservations are not due and has no queue
select fx_event(:'notDueEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '3 days'
));

-- Public ticket tier with capacity remaining after the due offer expires
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 2));

-- Free RSVP tier holding the event's only seat
select fx_event_ticket_type(:'rsvpTicketTypeID', :'rsvpEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier for the external-ready worker queue
select fx_event_ticket_type(:'externalQueueTicketTypeID', :'externalQueueEventID', jsonb_build_object('seats_total', 1));

-- Ticket tier for the reminder-due external hold
select fx_event_ticket_type(:'externalReminderTicketTypeID', :'externalReminderEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier reserved by the expired direct-charge hold
select fx_event_ticket_type(:'expiredHoldTicketTypeID', :'expiredHoldEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier with a free seat on the incomplete-venue event
select fx_event_ticket_type(:'incompleteVenueTicketTypeID', :'incompleteVenueEventID', jsonb_build_object('seats_total', 1));

-- Free ticket tier with a free seat on the closed-registration event
select fx_event_ticket_type(:'closedRegistrationTicketTypeID', :'closedRegistrationEventID', jsonb_build_object('seats_total', 1));

-- Paid ticket tier reserved by the reservations that are not due
select fx_event_ticket_type(:'notDueTicketTypeID', :'notDueEventID', jsonb_build_object('seats_total', 2));

-- Due and future offers reserving the ticket tier before reconciliation
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'dueOfferID',
        current_timestamp - interval '2 hours',
        :'eventID',
        :'ticketTypeID',
        current_timestamp - interval '1 hour',
        'waitlist',
        'pending',
        :'recipientID'
    ),
    (
        :'futureOfferID',
        current_timestamp,
        :'eventID',
        :'ticketTypeID',
        current_timestamp + interval '1 hour',
        'waitlist',
        'pending',
        :'futureRecipientID'
    );

-- Due RSVP offer that releases the event's only seat
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'rsvpDueOfferID',
    current_timestamp - interval '2 hours',
    :'rsvpEventID',
    :'rsvpTicketTypeID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpRecipientID'
);

-- Pending offer on the lowest-id event expiring in one hour
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'notDueOfferID',
    current_timestamp,
    :'notDueEventID',
    :'notDueTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'notDueOfferRecipientID'
);

-- Current positive price that requires the configured provider
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- Current free price for the RSVP tier
select fx_event_ticket_price_window(:'rsvpPriceWindowID', :'rsvpTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current positive price for the external-ready worker queue
select fx_event_ticket_price_window(:'externalQueuePriceWindowID', :'externalQueueTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Current positive price for the reminder-due external hold
select fx_event_ticket_price_window(:'externalReminderPriceWindowID', :'externalReminderTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- Current positive price for the incomplete-venue event
select fx_event_ticket_price_window(:'incompleteVenuePriceWindowID', :'incompleteVenueTicketTypeID', jsonb_build_object('amount_minor', 1000));

-- Current free price for the closed-registration event
select fx_event_ticket_price_window(:'closedRegistrationPriceWindowID', :'closedRegistrationTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Current positive price for the reservations that are not due
select fx_event_ticket_price_window(:'notDuePriceWindowID', :'notDueTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Queue head blocked until the configured payment provider becomes available
insert into event_waitlist (
    event_id,
    user_id,
    created_at,
    event_ticket_type_id
) values (
    :'eventID',
    :'queueRecipientID',
    current_timestamp,
    :'ticketTypeID'
);

-- RSVP queue head promoted by background reconciliation
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'rsvpEventID',
    :'rsvpTicketTypeID',
    :'rsvpQueueRecipientID'
);

-- External-ready paid queue head promoted without a Stripe provider
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'externalQueueEventID',
    :'externalQueueTicketTypeID',
    :'externalQueueRecipientID'
);

-- Paid queue head kept idle while the venue is incomplete
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'incompleteVenueEventID',
    :'incompleteVenueTicketTypeID',
    :'incompleteVenueRecipientID'
);

-- Free queue head kept idle while registration is closed
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'closedRegistrationEventID',
    :'closedRegistrationTicketTypeID',
    :'closedRegistrationRecipientID'
);

-- Reminder-due external hold claimed by the background worker
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
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
    current_timestamp - interval '48 hours',
    'KRW',
    :'externalReminderEventID',
    :'externalReminderPurchaseID',
    :'externalReminderTicketTypeID',
    current_timestamp + interval '12 hours',
    0,
    0,
    'pending',
    'External reminder admission',
    :'externalReminderRecipientID'
);

-- Direct-charge hold that expired one hour ago
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_checkout_session_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    2500,
    'direct-charge',
    'acct_reconciliation_worker',
    current_timestamp - interval '2 hours',
    'USD',
    :'expiredHoldEventID',
    :'expiredHoldPurchaseID',
    :'expiredHoldTicketTypeID',
    current_timestamp - interval '1 hour',
    'stripe',
    0,
    0,
    'reconcile-next-event-enrollment-expired-hold-session',
    'acct_reconciliation_worker',
    '{"connected_account_id":"acct_reconciliation_worker","display_name":"Worker Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Expired direct admission',
    :'expiredHoldRecipientID',
    '{}'::jsonb
);

-- Direct-charge hold on the lowest-id event expiring in 48 hours
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_checkout_session_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    2500,
    'direct-charge',
    'acct_reconciliation_worker',
    current_timestamp,
    'USD',
    :'notDueEventID',
    :'notDuePurchaseID',
    :'notDueTicketTypeID',
    current_timestamp + interval '48 hours',
    'stripe',
    0,
    0,
    'reconcile-next-event-enrollment-not-due-session',
    'acct_reconciliation_worker',
    '{"connected_account_id":"acct_reconciliation_worker","display_name":"Worker Fiscal Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Not due direct admission',
    :'notDuePurchaseRecipientID',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should claim and reconcile one event with a due offer
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should claim and reconcile one event with a due offer'
);

-- Should expire the due admission offer
select is(
    (select status from admission_offer where admission_offer_id = :'dueOfferID'),
    'expired',
    'Should expire the due admission offer'
);

-- Should audit the expired admission offer once
select is(
    (
        select count(*)::int
        from audit_log
        where action = 'admission_offer_expired'
        and resource_id = :'dueOfferID'
    ),
    1,
    'Should audit the expired admission offer once'
);

-- Should preserve admission offers whose deadlines are not due
select is(
    (select status from admission_offer where admission_offer_id = :'futureOfferID'),
    'pending',
    'Should preserve admission offers whose deadlines are not due'
);

-- Should skip events whose reservations are not due
select results_eq(
    format(
        $$
            select
                (select ao.status from admission_offer ao where ao.admission_offer_id = %L::uuid),
                (select ep.status from event_purchase ep where ep.event_purchase_id = %L::uuid)
        $$,
        :'notDueOfferID',
        :'notDuePurchaseID'
    ),
    $$ values ('pending'::text, 'pending'::text) $$,
    'Should skip events whose reservations are not due'
);

-- Should reconcile a free queue after an offer expires
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'rsvpEventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should reconcile a free queue after an offer expires'
);

-- Should persist a claim offer during background reconciliation
select results_eq(
    format(
        $$
            select
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'rsvpEventID',
        :'rsvpQueueRecipientID',
        :'rsvpEventID',
        :'rsvpQueueRecipientID'
    ),
    $$ values ('pending'::text, true) $$,
    'Should persist a claim offer during background reconciliation'
);

-- Should claim an external-ready paid queue without a Stripe provider
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'externalQueueEventID'::uuid,
        'group_id', :'externalGroupID'::uuid
    ),
    'Should claim an external-ready paid queue without a Stripe provider'
);

-- Should promote the external-ready paid queue head into an offer
select results_eq(
    format(
        $$
            select
                ao.event_ticket_type_id,
                ao.source,
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'externalQueueEventID',
        :'externalQueueRecipientID',
        :'externalQueueEventID',
        :'externalQueueRecipientID'
    ),
    format(
        $$
            values (
                %L::uuid,
                'waitlist'::text,
                'pending'::text,
                true
            )
        $$,
        :'externalQueueTicketTypeID'
    ),
    'Should promote the external-ready paid queue head into an offer'
);

-- Should claim a reminder-due external hold without a Stripe provider
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'externalReminderEventID'::uuid,
        'group_id', :'externalGroupID'::uuid
    ),
    'Should claim a reminder-due external hold without a Stripe provider'
);

-- Should mark the claimed external hold reminder as sent
select ok(
    (
        select external_payment_reminder_sent_at is not null
        from event_purchase
        where event_purchase_id = :'externalReminderPurchaseID'
    ),
    'Should mark the claimed external hold reminder as sent'
);

-- Should claim an event whose only pending work is an expired hold
select is(
    reconcile_next_event_enrollment()::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'expiredHoldEventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should claim an event whose only pending work is an expired hold'
);

-- Should expire the claimed direct-charge hold
select is(
    (select status from event_purchase where event_purchase_id = :'expiredHoldPurchaseID'),
    'expired',
    'Should expire the claimed direct-charge hold'
);

-- Should leave a paid queue idle while payment setup is unavailable
select is(
    reconcile_next_event_enrollment()::jsonb,
    null::jsonb,
    'Should leave a paid queue idle while payment setup is unavailable'
);

-- Should resume a paid queue after payment setup becomes available
select is(
    reconcile_next_event_enrollment('stripe')::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should resume a paid queue after payment setup becomes available'
);

-- Should replace the paid queue head with an admission offer
select results_eq(
    format(
        $$
            select
                ao.event_ticket_type_id,
                ao.source,
                ao.status,
                not exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.event_ticket_type_id = %L::uuid
                    and ew.user_id = %L::uuid
                )
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'eventID',
        :'ticketTypeID',
        :'queueRecipientID',
        :'eventID',
        :'queueRecipientID'
    ),
    format(
        $$
            values (
                %L::uuid,
                'waitlist'::text,
                'pending'::text,
                true
            )
        $$,
        :'ticketTypeID'
    ),
    'Should replace the paid queue head with an admission offer'
);

-- Should return no work after due and promotable enrollment is reconciled
select is(
    reconcile_next_event_enrollment('stripe')::jsonb,
    null::jsonb,
    'Should return no work after due and promotable enrollment is reconciled'
);

-- Should keep a free queue idle while registration is closed
select ok(
    exists (
        select 1
        from event_waitlist ew
        where ew.event_id = :'closedRegistrationEventID'
        and ew.user_id = :'closedRegistrationRecipientID'
    ),
    'Should keep a free queue idle while registration is closed'
);

-- Should keep a Stripe-paid queue idle while its venue is incomplete
select ok(
    exists (
        select 1
        from event_waitlist ew
        where ew.event_id = :'incompleteVenueEventID'
        and ew.user_id = :'incompleteVenueRecipientID'
    ),
    'Should keep a Stripe-paid queue idle while its venue is incomplete'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
