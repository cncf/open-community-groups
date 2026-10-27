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

-- Community owning the checkout event
select fx_community(:'communityID');

-- Community that does not own the checkout event
select fx_community(:'otherCommunityID');

-- User whose pending checkout is canceled
select fx_user(:'userID');

-- User queued for the tier released by the canceled checkout
select fx_user(:'waitlistUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_cancel_checkout',
        'seller_display_name', 'Cancel Checkout Fiscal Sponsor'
    )));

-- Event
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'in-person',
    'manual_tax_rate_ids', '{}'::text[],
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '1 day',
    'tax_calculation_mode', 'automatic',
    'venue_address', '1 Cancel Checkout Way',
    'venue_city', 'Cancel Checkout City',
    'venue_country_code', 'US',
    'venue_name', 'Cancel Checkout Hall',
    'venue_zip_code', '12345',
    'waitlist_enabled', true
));

-- Ticket type
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));

-- Pending purchase
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
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
    2500,
    'direct-charge',
    'acct_cancel',
    'USD',
    0,
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

-- Price window
select fx_event_ticket_price_window(:'priceWindowID', :'eventTicketTypeID', jsonb_build_object('amount_minor', 2500));

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
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'pendingPurchaseID'
    ),
    'pending',
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

-- Should expire the pending checkout
select is(
    (
        select status
        from event_purchase
        where event_purchase_id = :'pendingPurchaseID'
    ),
    'expired',
    'Should expire the pending checkout'
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
