-- Tests finding reusable event checkout purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledOfferID '79230000-0000-0000-0000-00000000002b'
\set communityID '79230000-0000-0000-0000-000000000001'
\set directRecoveryOfferID '79230000-0000-0000-0000-000000000020'
\set directRecoveryPurchaseID '79230000-0000-0000-0000-000000000021'
\set directRecoveryUserID '79230000-0000-0000-0000-000000000022'
\set eventCategoryID '79230000-0000-0000-0000-000000000002'
\set eventID '79230000-0000-0000-0000-000000000003'
\set groupCategoryID '79230000-0000-0000-0000-000000000006'
\set groupID '79230000-0000-0000-0000-000000000007'
\set offerID '79230000-0000-0000-0000-00000000001a'
\set offerPurchaseID '79230000-0000-0000-0000-00000000001b'
\set offerRecoveryExpiredOfferID '79230000-0000-0000-0000-000000000023'
\set offerRecoveryPurchaseID '79230000-0000-0000-0000-000000000024'
\set offerRecoveryReissuedOfferID '79230000-0000-0000-0000-000000000025'
\set offerRecoveryUserID '79230000-0000-0000-0000-000000000026'
\set offerUserID '79230000-0000-0000-0000-00000000001c'
\set pendingPurchaseID '79230000-0000-0000-0000-000000000010'
\set priceWindowAID '79230000-0000-0000-0000-000000000008'
\set priceWindowBID '79230000-0000-0000-0000-000000000009'
\set primaryUserID '79230000-0000-0000-0000-000000000012'
\set rankedCompletedPurchaseID '79230000-0000-0000-0000-000000000027'
\set rankedOfferID '79230000-0000-0000-0000-000000000028'
\set rankedRecoveryPurchaseID '79230000-0000-0000-0000-000000000029'
\set rankedUserID '79230000-0000-0000-0000-00000000002a'
\set recoveryOnlyPurchaseID '79230000-0000-0000-0000-000000000016'
\set recoveryOnlyPendingPurchaseID '79230000-0000-0000-0000-000000000019'
\set recoveryOnlyUserID '79230000-0000-0000-0000-000000000017'
\set recoveryPurchaseID '79230000-0000-0000-0000-000000000014'
\set recoveryReplacementPurchaseID '79230000-0000-0000-0000-000000000018'
\set recoveryUserID '79230000-0000-0000-0000-000000000015'
\set refundPendingOfferID '79230000-0000-0000-0000-00000000001d'
\set refundPendingPurchaseID '79230000-0000-0000-0000-00000000001e'
\set refundPendingUserID '79230000-0000-0000-0000-00000000001f'
\set refundPurchaseID '79230000-0000-0000-0000-000000000011'
\set secondaryUserID '79230000-0000-0000-0000-000000000013'
\set ticketTypeAID '79230000-0000-0000-0000-000000000004'
\set ticketTypeBID '79230000-0000-0000-0000-000000000005'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'directRecoveryUserID');
select fx_user(:'offerRecoveryUserID');
select fx_user(:'offerUserID');
select fx_user(:'primaryUserID');
select fx_user(:'rankedUserID');
select fx_user(:'recoveryOnlyUserID');
select fx_user(:'recoveryUserID');
select fx_user(:'refundPendingUserID');
select fx_user(:'secondaryUserID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_find_reusable',
        'seller_display_name', 'Reusable Purchase Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day'
));

-- Ticket types
select fx_event_ticket_type(:'ticketTypeAID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketTypeBID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 10,
    'title', 'VIP'
));

-- Price windows
select fx_event_ticket_price_window(:'priceWindowAID', :'ticketTypeAID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowBID', :'ticketTypeBID', jsonb_build_object('amount_minor', 4000));

-- Offer-linked pending purchase isolated from direct checkout lookups
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'offerID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    'General admission',
    :'offerUserID'
);

-- Offer retained while its late purchase payment is refunded automatically
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'refundPendingOfferID',
    2500,
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'checkout_pending',
    'General admission',
    :'refundPendingUserID'
);

-- Canceled offer whose identifier must not reuse holds linked to another offer
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'canceledOfferID',
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'canceled',
    :'offerUserID'
);

-- Offer issued after the user's direct purchase was refunded
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'directRecoveryOfferID',
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'directRecoveryUserID'
);

-- Expired offers whose late purchases entered refund recovery
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'offerRecoveryExpiredOfferID',
    2500,
    current_timestamp - interval '2 hours',
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp - interval '1 hour',
    'approval',
    'expired',
    'General admission',
    :'offerRecoveryUserID'
), (
    :'rankedOfferID',
    2500,
    current_timestamp - interval '2 hours',
    'USD',
    0,
    :'eventID',
    :'ticketTypeAID',
    current_timestamp - interval '1 hour',
    'approval',
    'expired',
    'General admission',
    :'rankedUserID'
);

-- Offer reissued while the expired offer purchase awaits refund recovery
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'offerRecoveryReissuedOfferID',
    :'eventID',
    :'ticketTypeAID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'offerRecoveryUserID'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    payment_provider_id,
    provider_charge_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    provider_total_minor,
    seller_snapshot,
    subtotal_excluding_tax_minor,
    tax_amount_minor,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    venue_snapshot
)
select
    fixtures.event_purchase_id::uuid,
    fixtures.admission_offer_id::uuid,
    fixtures.amount_minor,
    fixtures.created_at,
    fixtures.currency_code,
    fixtures.discount_amount_minor,
    fixtures.discount_code,
    fixtures.event_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.hold_expires_at,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_find',
    case when fixtures.status <> 'pending' then 0 end,
    'stripe',
    case when fixtures.status <> 'pending' then 'ch_' || fixtures.event_purchase_id end,
    case when fixtures.status <> 'pending' then 'cs_' || fixtures.event_purchase_id end,
    'acct_find',
    case when fixtures.status <> 'pending' then 'pi_' || fixtures.event_purchase_id end,
    case when fixtures.status <> 'pending' then fixtures.amount_minor end,
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    case when fixtures.status <> 'pending' then fixtures.amount_minor end,
    case when fixtures.status <> 'pending' then 0 end,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'pendingPurchaseID',
    null,
    2000,
    now() - interval '1 hour',
    'USD',
    500,
    ' save5 ',
    :'eventID',
    :'ticketTypeAID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'primaryUserID'
), (
    :'refundPurchaseID',
    null,
    4000,
    now() - interval '30 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-requested',
    'VIP',
    :'secondaryUserID'
), (
    :'recoveryOnlyPurchaseID',
    null,
    4000,
    now() - interval '15 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-recovery-pending',
    'VIP',
    :'recoveryOnlyUserID'
), (
    :'recoveryOnlyPendingPurchaseID',
    null,
    4000,
    now() - interval '5 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    now() + interval '10 minutes',
    'pending',
    'VIP',
    :'recoveryOnlyUserID'
), (
    :'recoveryPurchaseID',
    null,
    4000,
    now() - interval '20 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refund-recovery-pending',
    'VIP',
    :'recoveryUserID'
), (
    :'recoveryReplacementPurchaseID',
    null,
    4000,
    now() - interval '10 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'completed',
    'VIP',
    :'recoveryUserID'
), (
    :'directRecoveryPurchaseID',
    null,
    4000,
    now() - interval '40 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'refunded',
    'VIP',
    :'directRecoveryUserID'
), (
    :'offerRecoveryPurchaseID',
    :'offerRecoveryExpiredOfferID',
    2500,
    now() - interval '90 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeAID',
    null,
    'refund-recovery-pending',
    'General admission',
    :'offerRecoveryUserID'
), (
    :'rankedCompletedPurchaseID',
    null,
    4000,
    now() - interval '30 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeBID',
    null,
    'completed',
    'VIP',
    :'rankedUserID'
), (
    :'rankedRecoveryPurchaseID',
    :'rankedOfferID',
    2500,
    now() - interval '5 minutes',
    'USD',
    0,
    null,
    :'eventID',
    :'ticketTypeAID',
    null,
    'refund-recovery-pending',
    'General admission',
    :'rankedUserID'
)) as fixtures (
    event_purchase_id,
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
);

-- Active pending purchase linked to the selected admission offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_object_account_id,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    charge_model,
    connected_seller_id
) values (
    :'offerID',
    2500,
    'USD',
    0,
    :'eventID',
    :'offerPurchaseID',
    :'ticketTypeAID',
    current_timestamp + interval '15 minutes',
    'stripe',
    'acct_find',
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'offerUserID',
    '{}'::jsonb,
    'direct-charge',
    'acct_find'
);

-- Refund-pending purchase linked to its selected admission offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
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
    venue_snapshot,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor
) values (
    :'refundPendingOfferID',
    2500,
    'USD',
    0,
    :'eventID',
    :'refundPendingPurchaseID',
    :'ticketTypeAID',
    null,
    'stripe',
    'ch_find_refund',
    'cs_find_refund',
    'acct_find',
    'pi_find_refund',
    2500,
    '{"connected_account_id":"acct_find","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'refund-pending',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'refundPendingUserID',
    '{}'::jsonb,
    'direct-charge',
    'acct_find',
    0
);

-- Move the refunded direct purchase into recovery after its replacement offer
-- was issued, as a failed finalized refund does; the purchase and offer triggers
-- reject seeding a seat-holding direct purchase beside an active offer
update event_purchase
set status = 'refund-recovery-pending'
where event_purchase_id = :'directRecoveryPurchaseID';

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude offer-linked purchases from direct checkout reuse
select is_empty(
    format(
        $$
        select event_purchase_id
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerUserID'
    ),
    'Should exclude offer-linked purchases from direct checkout reuse'
);

-- Should exclude pending holds linked to another offer
select is_empty(
    format(
        $$
        select event_purchase_id
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerUserID',
        :'canceledOfferID'
    ),
    'Should exclude pending holds linked to another offer'
);

-- Should find a direct recovery purchase when checking out through an offer
select results_eq(
    format(
        $$
        select event_purchase_id, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'directRecoveryUserID',
        :'directRecoveryOfferID'
    ),
    format(
        $$ values (%L::uuid, 'false'::text, 'refund-recovery-pending'::text) $$,
        :'directRecoveryPurchaseID'
    ),
    'Should find a direct recovery purchase when checking out through an offer'
);

-- Should find an offer recovery purchase when checking out directly
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerRecoveryUserID'
    ),
    format(
        $$ values (%L::uuid, 'refund-recovery-pending'::text) $$,
        :'offerRecoveryPurchaseID'
    ),
    'Should find an offer recovery purchase when checking out directly'
);

-- Should find an offer recovery purchase when checking out through another offer
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerRecoveryUserID',
        :'offerRecoveryReissuedOfferID'
    ),
    format(
        $$ values (%L::uuid, 'refund-recovery-pending'::text) $$,
        :'offerRecoveryPurchaseID'
    ),
    'Should find an offer recovery purchase when checking out through another offer'
);

-- Should mark the pending purchase as matching when ticket and discount align
select results_eq(
    format($$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE5'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    $$ values ('true'::text) $$,
    'Should mark the pending purchase as matching when ticket and discount align'
);

-- Should mark the pending purchase as mismatched when the requested discount changes
select results_eq(
    format($$
        select matches_selection::text
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE10'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    $$ values ('false'::text) $$,
    'Should mark the pending purchase as mismatched when the requested discount changes'
);

-- Should retain an offer purchase while its automatic refund is pending
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'refundPendingUserID',
        :'refundPendingOfferID'
    ),
    format(
        $$ values (%L::uuid, 'refund-pending'::text) $$,
        :'refundPendingPurchaseID'
    ),
    'Should retain an offer purchase while its automatic refund is pending'
);

-- Should return a completed purchase on the requested path before a newer recovery purchase from another path
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
        $$,
        :'eventID',
        :'ticketTypeBID',
        :'rankedUserID'
    ),
    format(
        $$ values (%L::uuid, 'completed'::text) $$,
        :'rankedCompletedPurchaseID'
    ),
    'Should return a completed purchase on the requested path before a newer recovery purchase from another path'
);

-- Should return recovery before a newer pending replacement purchase
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'recoveryOnlyUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'refund-recovery-pending'::text) $$,
        :'recoveryOnlyPurchaseID'
    ),
    'Should return recovery before a newer pending replacement purchase'
);

-- Should return refund-requested purchases when no active pending purchase exists
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'secondaryUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'refund-requested'::text) $$,
        :'refundPurchaseID'
    ),
    'Should return refund-requested purchases when no active pending purchase exists'
);

-- Should return the active pending purchase for the requested user and event
select results_eq(
    format($$
        select event_purchase_id::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'SAVE5'
        )
    $$, :'eventID', :'ticketTypeAID', :'primaryUserID'),
    format($$ values (%L::text, 'pending'::text) $$, :'pendingPurchaseID'),
    'Should return the active pending purchase for the requested user and event'
);

-- Should return the newer completed replacement before an older recovery purchase
select results_eq(
    format($$
        select event_purchase_id::text, matches_selection::text, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )
    $$, :'eventID', :'ticketTypeBID', :'recoveryUserID'),
    format(
        $$ values (%L::text, 'true'::text, 'completed'::text) $$,
        :'recoveryReplacementPurchaseID'
    ),
    'Should return the newer completed replacement before an older recovery purchase'
);

-- Should reuse only the purchase linked to the selected offer
select results_eq(
    format(
        $$
        select event_purchase_id, status
        from prepare_event_checkout_find_existing_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'eventID',
        :'ticketTypeAID',
        :'offerUserID',
        :'offerID'
    ),
    format(
        $$ values (%L::uuid, 'pending'::text) $$,
        :'offerPurchaseID'
    ),
    'Should reuse only the purchase linked to the selected offer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
