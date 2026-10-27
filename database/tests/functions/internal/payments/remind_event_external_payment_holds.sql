-- Tests reminding event external payment checkout holds.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(3);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alreadyRemindedPurchaseID 'f30f0000-0000-0000-0000-000000000001'
\set alreadyRemindedUserID 'f30f0000-0000-0000-0000-000000000002'
\set communityID 'f30f0000-0000-0000-0000-000000000003'
\set duePurchaseID 'f30f0000-0000-0000-0000-000000000006'
\set dueUserID 'f30f0000-0000-0000-0000-000000000007'
\set eventCategoryID 'f30f0000-0000-0000-0000-000000000008'
\set eventID 'f30f0000-0000-0000-0000-000000000009'
\set groupCategoryID 'f30f0000-0000-0000-0000-00000000000e'
\set groupID 'f30f0000-0000-0000-0000-00000000000f'
\set ticketTypeID 'f30f0000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the reminder event
select fx_community(:'communityID');

-- Holder already reminded about the external payment
select fx_user(:'alreadyRemindedUserID');

-- Holder due the external payment reminder
select fx_user(:'dueUserID');

-- Event category for the reminder event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the reminder group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group shown in external payment reminder notifications
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Remind Event External Payment Holds Group'
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

-- External payment holds due and already reminded
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
