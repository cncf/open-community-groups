-- Tests reminding event external payment checkout holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alreadyRemindedPurchaseID 'f30f0000-0000-0000-0000-000000000001'
\set alreadyRemindedUserID 'f30f0000-0000-0000-0000-000000000002'
\set communityID 'f30f0000-0000-0000-0000-000000000003'
\set directPurchaseID 'f30f0000-0000-0000-0000-000000000004'
\set directUserID 'f30f0000-0000-0000-0000-000000000005'
\set duePurchaseID 'f30f0000-0000-0000-0000-000000000006'
\set dueUserID 'f30f0000-0000-0000-0000-000000000007'
\set eventCategoryID 'f30f0000-0000-0000-0000-000000000008'
\set eventID 'f30f0000-0000-0000-0000-000000000009'
\set expiredPurchaseID 'f30f0000-0000-0000-0000-00000000000a'
\set expiredUserID 'f30f0000-0000-0000-0000-00000000000b'
\set futurePurchaseID 'f30f0000-0000-0000-0000-00000000000c'
\set futureUserID 'f30f0000-0000-0000-0000-00000000000d'
\set groupCategoryID 'f30f0000-0000-0000-0000-00000000000e'
\set groupID 'f30f0000-0000-0000-0000-00000000000f'
\set shortPurchaseID 'f30f0000-0000-0000-0000-000000000010'
\set shortUserID 'f30f0000-0000-0000-0000-000000000011'
\set ticketTypeID 'f30f0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'alreadyRemindedUserID');
select fx_user(:'directUserID');
select fx_user(:'dueUserID');
select fx_user(:'expiredUserID');
select fx_user(:'futureUserID');
select fx_user(:'shortUserID');

-- Group shown in external payment reminder notifications
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Remind Event External Payment Holds Group',
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_remind_event_external_payment_holds'
    )
));

-- Event whose external payment holds are checked for reminders
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'external_payment_instructions', 'Send payment before the reminder deadline',
    'external_payment_url', 'https://pay.example.test/remind-event-external-payment-holds',
    'name', 'Remind Event External Payment Holds Event',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', current_timestamp + interval '2 days',
    'timezone', 'Europe/Amsterdam'
));

-- Ticket type shared by the reminder scenarios
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'External payment reminder admission'
));

-- Direct-charge pending purchase that is not eligible for external payment reminders
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
    'acct_remind_event_external_payment_holds',
    current_timestamp - interval '2 days',
    'USD',
    :'eventID',
    :'directPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '12 hours',
    'stripe',
    0,
    0,
    'remind-event-external-payment-holds-direct-session',
    'acct_remind_event_external_payment_holds',
    '{"connected_account_id":"acct_remind_event_external_payment_holds","display_name":"Reminder Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Direct reminder admission',
    :'directUserID',
    '{}'::jsonb
);

-- External payment purchases covering the reminder window branches
insert into event_purchase (
    amount_minor,
    charge_model,
    created_at,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    external_payment_reminder_sent_at,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'alreadyRemindedPurchaseID',
        :'ticketTypeID',
        current_timestamp - interval '1 hour',
        current_timestamp + interval '12 hours',
        'pending',
        'Already reminded external admission',
        :'alreadyRemindedUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'duePurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp + interval '12 hours',
        'pending',
        'Reminder due external admission',
        :'dueUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'expiredPurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp - interval '1 hour',
        'expired',
        'Expired external admission',
        :'expiredUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'futurePurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp + interval '2 days',
        'pending',
        'Future external admission',
        :'futureUserID'
    ),
    (
        2500,
        'external',
        current_timestamp,
        'USD',
        :'eventID',
        :'shortPurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp + interval '12 hours',
        'pending',
        'Short external admission',
        :'shortUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Send reminders twice to exercise the idempotent marker
select remind_event_external_payment_holds(
    (select e from event e where e.event_id = :'eventID'),
    (select g from "group" g where g.group_id = :'groupID'),
    '{"brand": "remind-event-external-payment-holds"}'::jsonb
);
select remind_event_external_payment_holds(
    (select e from event e where e.event_id = :'eventID'),
    (select g from "group" g where g.group_id = :'groupID'),
    '{"brand": "remind-event-external-payment-holds"}'::jsonb
);

-- Should ignore already-reminded holds
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-reminder'
        and n.user_id = :'alreadyRemindedUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'alreadyRemindedPurchaseID'::uuid
    ),
    0,
    'Should ignore already-reminded holds'
);

-- Should ignore expired holds
select results_eq(
    format(
        $$
            select
                external_payment_reminder_sent_at is null,
                (
                    select count(*)::int
                    from notification n
                    join notification_template_data ntd using (notification_template_data_id)
                    where n.kind = 'event-external-payment-reminder'
                    and n.user_id = %L::uuid
                    and (ntd.data->>'event_purchase_id')::uuid = %L::uuid
                )
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'expiredUserID',
        :'expiredPurchaseID',
        :'expiredPurchaseID'
    ),
    $$ values (true, 0::int) $$,
    'Should ignore expired holds'
);

-- Should ignore external holds outside the reminder window
select ok(
    (
        select external_payment_reminder_sent_at is null
        from event_purchase
        where event_purchase_id = :'futurePurchaseID'
    ),
    'Should ignore external holds outside the reminder window'
);

-- Should ignore non-external holds
select results_eq(
    format(
        $$
            select
                external_payment_reminder_sent_at is null,
                (
                    select count(*)::int
                    from notification n
                    where n.kind = 'event-external-payment-reminder'
                    and n.user_id = %L::uuid
                )
            from event_purchase
            where event_purchase_id = %L::uuid
        $$,
        :'directUserID',
        :'directPurchaseID'
    ),
    $$ values (true, 0::int) $$,
    'Should ignore non-external holds'
);

-- Should ignore short external holds
select ok(
    (
        select external_payment_reminder_sent_at is null
        from event_purchase
        where event_purchase_id = :'shortPurchaseID'
    ),
    'Should ignore short external holds'
);

-- Should mark reminder-due external holds
select ok(
    (
        select external_payment_reminder_sent_at is not null
        from event_purchase
        where event_purchase_id = :'duePurchaseID'
    ),
    'Should mark reminder-due external holds'
);

-- Should notify reminder-due external holders once
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-reminder'
        and n.user_id = :'dueUserID'
        and (ntd.data->>'event_purchase_id')::uuid = :'duePurchaseID'::uuid
    ),
    1,
    'Should notify reminder-due external holders once'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
