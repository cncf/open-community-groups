-- Tests preparing external event checkout purchases.
-- Split from prepare_event_checkout_purchase.sql because the external checkout
-- scenarios need their own groups, events and operator payment window config.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(18);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '79110000-0000-0000-0000-000000000001'
\set eventCategoryID '79110000-0000-0000-0000-000000000002'
\set externalCapEventID '79110000-0000-0000-0000-000000000084'
\set externalCapPriceWindowID '79110000-0000-0000-0000-00000000008e'
\set externalCapTicketTypeID '79110000-0000-0000-0000-000000000089'
\set externalCapUserID '79110000-0000-0000-0000-000000000093'
\set externalClosedRegEventID '79110000-0000-0000-0000-00000000009c'
\set externalClosedRegOfferID '79110000-0000-0000-0000-00000000009d'
\set externalClosedRegPriceWindowID '79110000-0000-0000-0000-00000000009e'
\set externalClosedRegTicketTypeID '79110000-0000-0000-0000-00000000009f'
\set externalClosedRegUserID '79110000-0000-0000-0000-0000000000a0'
\set externalEventID '79110000-0000-0000-0000-000000000083'
\set externalMaxEventID '79110000-0000-0000-0000-000000000085'
\set externalMaxPriceWindowID '79110000-0000-0000-0000-00000000008f'
\set externalMaxTicketTypeID '79110000-0000-0000-0000-00000000008a'
\set externalMaxUserID '79110000-0000-0000-0000-000000000094'
\set externalOfferID '79110000-0000-0000-0000-000000000098'
\set externalOfferUserID '79110000-0000-0000-0000-000000000097'
\set externalPriceWindowID '79110000-0000-0000-0000-00000000008d'
\set externalReadyGroupID '79110000-0000-0000-0000-000000000081'
\set externalRetryOfferID '79110000-0000-0000-0000-00000000009a'
\set externalRetryUserID '79110000-0000-0000-0000-00000000009b'
\set externalTicketTypeID '79110000-0000-0000-0000-000000000088'
\set externalUnreadyEventID '79110000-0000-0000-0000-000000000087'
\set externalUnreadyGroupID '79110000-0000-0000-0000-000000000082'
\set externalUnreadyPriceWindowID '79110000-0000-0000-0000-000000000091'
\set externalUnreadyTicketTypeID '79110000-0000-0000-0000-00000000008c'
\set externalUnreadyUserID '79110000-0000-0000-0000-000000000096'
\set externalUserID '79110000-0000-0000-0000-000000000092'
\set externalWindowEventID '79110000-0000-0000-0000-000000000086'
\set externalWindowOfferID '79110000-0000-0000-0000-000000000099'
\set externalWindowPriceWindowID '79110000-0000-0000-0000-000000000090'
\set externalWindowTicketTypeID '79110000-0000-0000-0000-00000000008b'
\set externalWindowUserID '79110000-0000-0000-0000-000000000095'
\set groupCategoryID '79110000-0000-0000-0000-000000000010'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Operator allowlist and payment window limits for external checkout
insert into external_payments_config (
    allowed_countries,
    default_payment_window_hours,
    max_payment_window_hours
) values (
    array['KR']::text[],
    72,
    336
);

-- Community
select fx_community(:'communityID');

-- Baseline categories and users
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'externalCapUserID');
select fx_user(:'externalClosedRegUserID');
select fx_user(:'externalMaxUserID');
select fx_user(:'externalOfferUserID');
select fx_user(:'externalRetryUserID');
select fx_user(:'externalUnreadyUserID');
select fx_user(:'externalUserID');
select fx_user(:'externalWindowUserID');

-- Allowlisted group with external payments enabled for ready checkout
select fx_group(:'externalReadyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'external_payments_enabled', true,
    'external_payments_seller_display_name', 'External Payee Co'
));

-- Stripe-ready group with external payments disabled for no-fallback conflicts
select fx_group(:'externalUnreadyGroupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'country_code', 'KR',
    'payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_external_unready',
        'seller_display_name', 'External Unready Fiscal Sponsor'
    )
));

-- External-ready event with a 48-hour payment window
select fx_event(:'externalEventID', :'externalReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_instructions', 'Wire to account 123',
    'external_payment_url', 'https://pay.example.test/prepare',
    'external_payment_window_hours', 48,
    'payment_currency_code', 'KRW',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '7 days'
));

-- External-ready event whose hold is capped by a near starts_at
select fx_event(:'externalCapEventID', :'externalReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/prepare-cap',
    'payment_currency_code', 'KRW',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 hours'
));

-- External-ready event whose window hours exceed the configured max
select fx_event(:'externalMaxEventID', :'externalReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/prepare-max',
    'external_payment_window_hours', 500,
    'payment_currency_code', 'KRW',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '60 days'
));

-- Started event whose external hold would expire immediately on offer claim
select fx_event(:'externalWindowEventID', :'externalReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() + interval '90 minutes',
    'external_payment_url', 'https://pay.example.test/prepare-window',
    'payment_currency_code', 'KRW',
    'published', true,
    'published_at', now(),
    'starts_at', now() - interval '30 minutes'
));

-- External-ready event whose public registration window has already closed
select fx_event(:'externalClosedRegEventID', :'externalReadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/prepare-closed-reg',
    'payment_currency_code', 'KRW',
    'published', true,
    'published_at', now(),
    'registration_ends_at', now() - interval '1 hour',
    'starts_at', now() + interval '7 days'
));

-- External-marked event on a Stripe-ready group that is not externally eligible
select fx_event(:'externalUnreadyEventID', :'externalUnreadyGroupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_url', 'https://pay.example.test/prepare-unready',
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days',
    'venue_address', '1 Main St',
    'venue_city', 'Portland',
    'venue_country_code', 'US',
    'venue_name', 'Venue',
    'venue_zip_code', '97201'
));

-- Ticket types
select fx_event_ticket_type(:'externalTicketTypeID', :'externalEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'External admission'
));
select fx_event_ticket_type(:'externalCapTicketTypeID', :'externalCapEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'externalMaxTicketTypeID', :'externalMaxEventID', jsonb_build_object('seats_total', 10));
select fx_event_ticket_type(:'externalWindowTicketTypeID', :'externalWindowEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'External window admission'
));
select fx_event_ticket_type(:'externalClosedRegTicketTypeID', :'externalClosedRegEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'External closed registration admission'
));
select fx_event_ticket_type(:'externalUnreadyTicketTypeID', :'externalUnreadyEventID', jsonb_build_object('seats_total', 10));

-- Positive price windows for external checkout scenarios
select fx_event_ticket_price_window(:'externalPriceWindowID', :'externalTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalCapPriceWindowID', :'externalCapTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalMaxPriceWindowID', :'externalMaxTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalWindowPriceWindowID', :'externalWindowTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalClosedRegPriceWindowID', :'externalClosedRegTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'externalUnreadyPriceWindowID', :'externalUnreadyTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Pending offer claimed into a longer external payment window
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
    :'externalOfferID',
    5000,
    'KRW',
    0,
    :'externalEventID',
    :'externalTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    'External admission',
    :'externalOfferUserID'
);

-- Checkout-pending offer retried into a longer external hold
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
    :'externalRetryOfferID',
    5000,
    'KRW',
    0,
    :'externalEventID',
    :'externalTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    'External admission',
    :'externalRetryUserID'
);

-- Pending offer used to claim after the event start has passed
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
    :'externalWindowOfferID',
    5000,
    'KRW',
    0,
    :'externalWindowEventID',
    :'externalWindowTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    'External window admission',
    :'externalWindowUserID'
);

-- Pending invitation used to claim after the public registration window closed
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
    :'externalClosedRegOfferID',
    5000,
    'KRW',
    0,
    :'externalClosedRegEventID',
    :'externalClosedRegTicketTypeID',
    current_timestamp + interval '2 days',
    'organizer_invitation',
    'pending',
    'External closed registration admission',
    :'externalClosedRegUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should prepare an external paid checkout with zero fees
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            null,
            250
        )$$,
        :'communityID',
        :'externalEventID',
        :'externalTicketTypeID',
        :'externalUserID'
    ),
    'Should prepare an external paid checkout with zero fees'
);

-- Should persist an external charge model without a provider or fee snapshot
select results_eq(
    format(
        $$
            select
                charge_model,
                payment_provider_id,
                platform_fee_bps,
                provisional_platform_fee_amount_minor,
                seller_snapshot
            from event_purchase
            where event_id = %L::uuid
            and user_id = %L::uuid
            and status = 'pending'
        $$,
        :'externalEventID',
        :'externalUserID'
    ),
    $$
        values (
            'external'::text,
            null::text,
            0,
            0::bigint,
            null::jsonb
        )
    $$,
    'Should persist an external charge model without a provider or fee snapshot'
);

-- Should cap the external hold by the event payment window hours
select is(
    (
        select hold_expires_at
        from event_purchase
        where event_id = :'externalEventID'::uuid
        and user_id = :'externalUserID'::uuid
        and status = 'pending'
    ),
    current_timestamp + interval '48 hours',
    'Should cap the external hold by the event payment window hours'
);

-- Should enqueue one external pending-payment notification for the new hold
select results_eq(
    format(
        $$
            select
                n.kind,
                n.user_id,
                ntd.data->>'event_purchase_id'
            from notification n
            join notification_template_data ntd using (notification_template_data_id)
            where n.user_id = %L::uuid
        $$,
        :'externalUserID'
    ),
    format(
        $$
            select
                'event-external-payment-pending'::text,
                ep.user_id,
                ep.event_purchase_id::text
            from event_purchase ep
            where ep.event_id = %L::uuid
            and ep.user_id = %L::uuid
            and ep.status = 'pending'
        $$,
        :'externalEventID',
        :'externalUserID'
    ),
    'Should enqueue one external pending-payment notification for the new hold'
);

-- Should reuse an equivalent external hold
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe'
        )$$,
        :'communityID',
        :'externalEventID',
        :'externalTicketTypeID',
        :'externalUserID'
    ),
    'Should reuse an equivalent external hold'
);

-- Should keep a single external pending-payment notification after reuse
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-external-payment-pending'
        and n.user_id = :'externalUserID'
        and (ntd.data->>'event_id')::uuid = :'externalEventID'::uuid
    ),
    1,
    'Should keep a single external pending-payment notification after reuse'
);

-- Should claim an offer into an external checkout hold
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )$$,
        :'communityID',
        :'externalEventID',
        :'externalTicketTypeID',
        :'externalOfferUserID',
        :'externalOfferID'
    ),
    'Should claim an offer into an external checkout hold'
);

-- Should persist the raised offer deadline with the external hold
select results_eq(
    format(
        $$
            select
                ao.expires_at,
                ep.hold_expires_at
            from admission_offer ao
            join event_purchase ep on ep.admission_offer_id = ao.admission_offer_id
            where ao.admission_offer_id = %L::uuid
            and ep.status = 'pending'
        $$,
        :'externalOfferID'
    ),
    $$
        values (
            current_timestamp + interval '48 hours',
            current_timestamp + interval '48 hours'
        )
    $$,
    'Should persist the raised offer deadline with the external hold'
);

-- Should prepare an external checkout capped by event start
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe'
        )$$,
        :'communityID',
        :'externalCapEventID',
        :'externalCapTicketTypeID',
        :'externalCapUserID'
    ),
    'Should prepare an external checkout capped by event start'
);

-- Should set hold expiry to the event start for a near-term external event
select is(
    (
        select hold_expires_at
        from event_purchase
        where event_id = :'externalCapEventID'::uuid
        and user_id = :'externalCapUserID'::uuid
        and status = 'pending'
    ),
    now() + interval '2 hours',
    'Should set hold expiry to the event start for a near-term external event'
);

-- Should prepare an external checkout with an oversized event window
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe'
        )$$,
        :'communityID',
        :'externalMaxEventID',
        :'externalMaxTicketTypeID',
        :'externalMaxUserID'
    ),
    'Should prepare an external checkout with an oversized event window'
);

-- Should persist a hold capped at the maximum payment window
select is(
    (
        select hold_expires_at
        from event_purchase
        where event_id = :'externalMaxEventID'::uuid
        and user_id = :'externalMaxUserID'::uuid
        and status = 'pending'
    ),
    current_timestamp + interval '336 hours',
    'Should persist a hold capped at the maximum payment window'
);

-- Should reject external checkout when eligibility is lost without Stripe fallback
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'externalUnreadyEventID'::uuid,
        :'externalUnreadyTicketTypeID'::uuid,
        :'externalUnreadyUserID'::uuid,
        null,
        'stripe'
    ),
    '{"conflict":"payment-setup-unavailable"}'::jsonb,
    'Should reject external checkout when eligibility is lost without Stripe fallback'
);

-- Should reject an external hold that would expire immediately
select is(
    prepare_event_checkout_purchase(
        :'communityID'::uuid,
        :'externalWindowEventID'::uuid,
        :'externalWindowTicketTypeID'::uuid,
        :'externalWindowUserID'::uuid,
        null,
        'stripe',
        null,
        :'externalWindowOfferID'::uuid
    ),
    '{"conflict":"payment-window-unavailable"}'::jsonb,
    'Should reject an external hold that would expire immediately'
);

-- Should create an external hold for an invitation after registration has closed
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )$$,
        :'communityID',
        :'externalClosedRegEventID',
        :'externalClosedRegTicketTypeID',
        :'externalClosedRegUserID',
        :'externalClosedRegOfferID'
    ),
    'Should create an external hold for an invitation after registration has closed'
);

-- Should keep an invitation hold open after the public registration window closes
select is(
    (
        select hold_expires_at
        from event_purchase
        where event_id = :'externalClosedRegEventID'::uuid
        and user_id = :'externalClosedRegUserID'::uuid
        and status = 'pending'
    ),
    current_timestamp + interval '72 hours',
    'Should keep an invitation hold open after the public registration window closes'
);

-- Should raise a checkout-pending offer deadline on external hold retry
select lives_ok(
    format(
        $$select prepare_event_checkout_purchase(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            'stripe',
            null,
            %L::uuid
        )$$,
        :'communityID',
        :'externalEventID',
        :'externalTicketTypeID',
        :'externalRetryUserID',
        :'externalRetryOfferID'
    ),
    'Should raise a checkout-pending offer deadline on external hold retry'
);

-- Should persist the retry deadline with the new external hold
select results_eq(
    format(
        $$
            select
                ao.expires_at,
                ep.hold_expires_at
            from admission_offer ao
            join event_purchase ep on ep.admission_offer_id = ao.admission_offer_id
            where ao.admission_offer_id = %L::uuid
            and ep.status = 'pending'
        $$,
        :'externalRetryOfferID'
    ),
    $$
        values (
            current_timestamp + interval '48 hours',
            current_timestamp + interval '48 hours'
        )
    $$,
    'Should persist the retry deadline with the new external hold'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
