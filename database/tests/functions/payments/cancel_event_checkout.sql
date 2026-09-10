-- Tests canceling pending event checkouts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79310000-0000-0000-0000-000000000001'
\set discountCodeID '79310000-0000-0000-0000-000000000002'
\set eventCategoryID '79310000-0000-0000-0000-000000000003'
\set eventID '79310000-0000-0000-0000-000000000004'
\set eventTicketTypeID '79310000-0000-0000-0000-000000000005'
\set groupCategoryID '79310000-0000-0000-0000-000000000006'
\set groupID '79310000-0000-0000-0000-000000000007'
\set otherCommunityID '79310000-0000-0000-0000-000000000008'
\set pendingPurchaseID '79310000-0000-0000-0000-000000000009'
\set priceWindowID '79310000-0000-0000-0000-000000000010'
\set userID '79310000-0000-0000-0000-000000000011'
\set waitlistUserID '79310000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_community(:'otherCommunityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'userID');
select fx_user(:'waitlistUserID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_cancel_checkout',
        'seller_display_name', 'Cancel Checkout Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day',
    'waitlist_enabled', true
));

-- Ticket type
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount code
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
    :'discountCodeID',
    500,
    0,
    true,
    'SAVE5',
    :'eventID',
    'fixed_amount',
    'Save 5'
);

-- Pending purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_checkout_url,
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
    :'pendingPurchaseID',
    2000,
    'direct-charge',
    'acct_cancel',
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'eventID',
    :'eventTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_cancel_checkout',
    'https://checkout.stripe.test/cs_cancel_checkout',
    'acct_cancel',
    '{"connected_account_id":"acct_cancel","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'userID',
    '{}'::jsonb
);

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, user_id, status)
values (
    :'eventID',
    :'userID',
    'registration-questions-pending'
);

-- FIFO waitlist entry promoted only after the direct checkout is canceled
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'eventID',
    :'eventTicketTypeID',
    :'waitlistUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore checkouts outside the requested community
select lives_ok(
    format($$select cancel_event_checkout(
        %L::uuid,
        %L::uuid,
        %L::uuid
    )$$, :'otherCommunityID', :'eventID', :'userID'),
    'Should ignore checkouts outside the requested community'
);

-- Should leave unmatched community checkout state unchanged
select results_eq(
    format($$
        select
            (
                select available
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
    $$, :'discountCodeID', :'pendingPurchaseID', :'eventID', :'userID'),
    $$ values (0::int, 'pending'::text, 1::int) $$,
    'Should leave unmatched community checkout state unchanged'
);

-- Should cancel the attendee's active pending checkout
select lives_ok(
    format($$select cancel_event_checkout(
        %L::uuid,
        %L::uuid,
        %L::uuid,
        'stripe'
    )$$, :'communityID', :'eventID', :'userID'),
    'Should cancel the attendee active pending checkout'
);

-- Should expire the pending checkout and restore the reserved discount usage
select results_eq(
    format($$
        select
            (
                select available
                from event_discount_code
                where event_discount_code_id = %L::uuid
            ),
            (
                select hold_expires_at <= current_timestamp
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = %L::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = %L::uuid
                and user_id = %L::uuid
            )
    $$, :'discountCodeID', :'pendingPurchaseID', :'pendingPurchaseID', :'eventID', :'userID'),
    $$ values (1::int, true, 'expired'::text, 0::int) $$,
    'Should expire the pending checkout, release registration hold, and restore discount usage'
);

-- Should promote the FIFO queue after direct checkout capacity is released
select results_eq(
    format(
        $$
            select
                (
                    select user_id
                    from admission_offer
                    where event_id = %L::uuid
                    and status = 'pending'
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'eventID',
        :'eventID'
    ),
    format($$ values (%L::uuid, 0::bigint) $$, :'waitlistUserID'),
    'Should promote the FIFO queue after direct checkout capacity is released'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
