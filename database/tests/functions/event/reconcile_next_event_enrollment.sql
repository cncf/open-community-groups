-- Tests claiming the next event that requires enrollment reconciliation.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '5e050000-0000-0000-0000-000000000001'
\set dueOfferID '5e050000-0000-0000-0000-000000000002'
\set eventCategoryID '5e050000-0000-0000-0000-000000000003'
\set eventID '5e050000-0000-0000-0000-000000000004'
\set externalGroupID '5e050000-0000-0000-0000-000000000011'
\set externalQueueEventID '5e050000-0000-0000-0000-000000000012'
\set externalQueueRecipientID '5e050000-0000-0000-0000-000000000013'
\set externalQueueTicketTypeID '5e050000-0000-0000-0000-000000000014'
\set externalReminderEventID '5e050000-0000-0000-0000-000000000015'
\set externalReminderPurchaseID '5e050000-0000-0000-0000-000000000016'
\set externalReminderRecipientID '5e050000-0000-0000-0000-000000000017'
\set externalReminderTicketTypeID '5e050000-0000-0000-0000-000000000018'
\set futureOfferID '5e050000-0000-0000-0000-000000000005'
\set futureRecipientID '5e050000-0000-0000-0000-000000000006'
\set groupCategoryID '5e050000-0000-0000-0000-000000000007'
\set groupID '5e050000-0000-0000-0000-000000000008'
\set priceWindowID '5e050000-0000-0000-0000-00000000000b'
\set queueRecipientID '5e050000-0000-0000-0000-00000000000c'
\set recipientID '5e050000-0000-0000-0000-000000000009'
\set rsvpDueOfferID '5e050000-0000-0000-0000-00000000000d'
\set rsvpEventID '5e050000-0000-0000-0000-00000000000e'
\set rsvpQueueRecipientID '5e050000-0000-0000-0000-00000000000f'
\set rsvpRecipientID '5e050000-0000-0000-0000-000000000010'
\set ticketTypeID '5e050000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'externalQueueRecipientID');
select fx_user(:'externalReminderRecipientID');
select fx_user(:'rsvpQueueRecipientID');
select fx_user(:'rsvpRecipientID');

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

select fx_user(:'futureRecipientID', jsonb_build_object('username', 'future'));
select fx_user(:'queueRecipientID', jsonb_build_object('username', 'queue'));
select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-next-event-enrollment'));

-- Group with a configured recipient for paid queue recovery
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', '{"provider": "stripe", "recipient_id": "acct_reconciliation_worker", "seller_display_name": "Worker Fiscal Sponsor"}'::jsonb));

-- Allowlisted group with external payments enabled for worker claims
select fx_group(:'externalGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true
));

-- Published event with one due and one future admission offer
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- RSVP event with a due offer and one waiting recipient
select fx_event(:'rsvpEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Public ticket tier with capacity remaining after the due offer expires
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object('seats_total', 2));

-- Current positive price that requires the configured provider
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- RSVP events without a specialized ticket fixture use a default tier
select fx_event_ticket_type(gen_random_uuid(), e.event_id, jsonb_build_object('seats_total', 1))
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free price for the RSVP event's default tier
select fx_event_ticket_price_window(gen_random_uuid(), ett.event_ticket_type_id, jsonb_build_object('amount_minor', 0))
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

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
    (select event_ticket_type_id from event_ticket_type where event_id = :'rsvpEventID' limit 1),
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'rsvpRecipientID'
);

-- RSVP queue head promoted by background reconciliation
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'rsvpEventID',
    (select event_ticket_type_id from event_ticket_type where event_id = :'rsvpEventID' limit 1),
    :'rsvpQueueRecipientID'
);

-- External-ready paid event claimed after Stripe work is exhausted
select fx_event(:'externalQueueEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/worker-queue',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '1 day',
    'waitlist_enabled', true
));

-- Paid ticket tier for the external-ready worker queue
select fx_event_ticket_type(:'externalQueueTicketTypeID', :'externalQueueEventID', jsonb_build_object('seats_total', 1));

-- Current positive price for the external-ready worker queue
select fx_event_ticket_price_window(gen_random_uuid(), :'externalQueueTicketTypeID', jsonb_build_object('amount_minor', 5000));

-- External-ready paid queue head promoted without a Stripe provider
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (
    :'externalQueueEventID',
    :'externalQueueTicketTypeID',
    :'externalQueueRecipientID'
);

-- Event hosting a reminder-due external pending hold
select fx_event(:'externalReminderEventID', :'externalGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/worker-reminder',
    'payment_currency_code', 'KRW',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket tier for the reminder-due external hold
select fx_event_ticket_type(:'externalReminderTicketTypeID', :'externalReminderEventID', jsonb_build_object('seats_total', 1));

-- Current positive price for the reminder-due external hold
select fx_event_ticket_price_window(gen_random_uuid(), :'externalReminderTicketTypeID', jsonb_build_object('amount_minor', 5000));

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

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
