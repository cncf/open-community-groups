-- Tests detecting pending external payment holds due their reminder.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set alreadyRemindedPurchaseID 'e7a20000-0000-0000-0000-000000000001'
\set alreadyRemindedUserID 'e7a20000-0000-0000-0000-000000000002'
\set communityID 'e7a20000-0000-0000-0000-000000000003'
\set directPurchaseID 'e7a20000-0000-0000-0000-000000000004'
\set directUserID 'e7a20000-0000-0000-0000-000000000005'
\set duePurchaseID 'e7a20000-0000-0000-0000-000000000006'
\set dueUserID 'e7a20000-0000-0000-0000-000000000007'
\set eventCategoryID 'e7a20000-0000-0000-0000-000000000008'
\set eventID 'e7a20000-0000-0000-0000-000000000009'
\set expiredPurchaseID 'e7a20000-0000-0000-0000-000000000010'
\set expiredUserID 'e7a20000-0000-0000-0000-000000000011'
\set groupCategoryID 'e7a20000-0000-0000-0000-000000000012'
\set groupID 'e7a20000-0000-0000-0000-000000000013'
\set noDeadlinePurchaseID 'e7a20000-0000-0000-0000-000000000014'
\set noDeadlineUserID 'e7a20000-0000-0000-0000-000000000015'
\set nonPendingPurchaseID 'e7a20000-0000-0000-0000-000000000016'
\set nonPendingUserID 'e7a20000-0000-0000-0000-000000000017'
\set outsideWindowPurchaseID 'e7a20000-0000-0000-0000-000000000018'
\set outsideWindowUserID 'e7a20000-0000-0000-0000-000000000019'
\set shortPurchaseID 'e7a20000-0000-0000-0000-000000000020'
\set shortUserID 'e7a20000-0000-0000-0000-000000000021'
\set ticketTypeID 'e7a20000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the reminder event
select fx_community(:'communityID');

-- Holder already reminded about the external payment
select fx_user(:'alreadyRemindedUserID');

-- Holder of the direct-charge checkout hold
select fx_user(:'directUserID');

-- Holder due the external payment reminder
select fx_user(:'dueUserID');

-- Holder of the external hold past its deadline
select fx_user(:'expiredUserID');

-- Holder of the external hold without a deadline
select fx_user(:'noDeadlineUserID');

-- Holder of the expired external purchase
select fx_user(:'nonPendingUserID');

-- Holder of the external hold expiring after the reminder window
select fx_user(:'outsideWindowUserID');

-- Holder of the external hold shorter than the reminder lead time
select fx_user(:'shortUserID');

-- Event category for the reminder event
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for the reminder group
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the reminder event
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event whose checkout holds are checked for reminders
select fx_event(:'eventID', :'groupID', :'eventCategoryID');

-- Ticket type shared by the reminder holds
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 20,
    'title', 'External payment reminder admission'
));

-- Direct-charge pending hold inside the reminder window
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
    'acct_event_purchase_external_reminder_is_due',
    current_timestamp - interval '2 days',
    'USD',
    :'eventID',
    :'directPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '12 hours',
    'stripe',
    0,
    0,
    'event-purchase-external-reminder-is-due-direct-session',
    'acct_event_purchase_external_reminder_is_due',
    '{"connected_account_id":"acct_event_purchase_external_reminder_is_due","display_name":"Reminder Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Direct reminder admission',
    :'directUserID',
    '{}'::jsonb
);

-- External payment purchases covering each reminder predicate branch
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
        current_timestamp - interval '3 days',
        'USD',
        :'eventID',
        :'expiredPurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp - interval '1 hour',
        'pending',
        'Expired hold external admission',
        :'expiredUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'noDeadlinePurchaseID',
        :'ticketTypeID',
        null,
        null,
        'pending',
        'No deadline external admission',
        :'noDeadlineUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'nonPendingPurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp + interval '12 hours',
        'expired',
        'Expired external admission',
        :'nonPendingUserID'
    ),
    (
        2500,
        'external',
        current_timestamp - interval '2 days',
        'USD',
        :'eventID',
        :'outsideWindowPurchaseID',
        :'ticketTypeID',
        null,
        current_timestamp + interval '2 days',
        'pending',
        'Outside window external admission',
        :'outsideWindowUserID'
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
        'Short hold external admission',
        :'shortUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should report already-reminded holds as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'alreadyRemindedPurchaseID')
    ),
    false,
    'Should report already-reminded holds as not due'
);

-- Should report direct-charge holds as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'directPurchaseID')
    ),
    false,
    'Should report direct-charge holds as not due'
);

-- Should report expired holds as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'expiredPurchaseID')
    ),
    false,
    'Should report expired holds as not due'
);

-- Should report holds expiring after the reminder window as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'outsideWindowPurchaseID')
    ),
    false,
    'Should report holds expiring after the reminder window as not due'
);

-- Should report holds without a deadline as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'noDeadlinePurchaseID')
    ),
    false,
    'Should report holds without a deadline as not due'
);

-- Should report non-pending purchases as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'nonPendingPurchaseID')
    ),
    false,
    'Should report non-pending purchases as not due'
);

-- Should report reminder-due external holds as due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'duePurchaseID')
    ),
    true,
    'Should report reminder-due external holds as due'
);

-- Should report short holds as not due
select is(
    event_purchase_external_reminder_is_due(
        (select ep from event_purchase ep where ep.event_purchase_id = :'shortPurchaseID')
    ),
    false,
    'Should report short holds as not due'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
