-- Tests validating event checkout ticket selection and pricing.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(19);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeUserID '79260000-0000-0000-0000-000000000022'
\set communityID '79260000-0000-0000-0000-000000000001'
\set eventCategoryID '79260000-0000-0000-0000-000000000002'
\set exhaustedDiscountUserID '79260000-0000-0000-0000-000000000025'
\set expiredPriceWindowID '79260000-0000-0000-0000-000000000037'
\set fixedDiscountUserID '79260000-0000-0000-0000-000000000026'
\set freeDiscountID '79260000-0000-0000-0000-000000000016'
\set groupCategoryID '79260000-0000-0000-0000-000000000010'
\set groupID '79260000-0000-0000-0000-000000000011'
\set inactiveDiscountID '79260000-0000-0000-0000-000000000017'
\set inactiveEventID '79260000-0000-0000-0000-000000000005'
\set inactivePriceWindowID '79260000-0000-0000-0000-000000000015'
\set inactiveTicketTypeID '79260000-0000-0000-0000-000000000009'
\set inactiveUserID '79260000-0000-0000-0000-000000000029'
\set ineffectiveDiscountPriceWindowID '79260000-0000-0000-0000-00000000004a'
\set ineffectiveDiscountTicketTypeID '79260000-0000-0000-0000-00000000004b'
\set invalidDiscountUserID '79260000-0000-0000-0000-000000000023'
\set invitedUserID '79260000-0000-0000-0000-000000000032'
\set limitedDiscountID '79260000-0000-0000-0000-000000000018'
\set mainEventID '79260000-0000-0000-0000-000000000003'
\set missingTicketTypeID '79260000-0000-0000-0000-000000000034'
\set noActivePriceTicketTypeID '79260000-0000-0000-0000-000000000035'
\set offerID '79260000-0000-0000-0000-000000000045'
\set offerUserID '79260000-0000-0000-0000-000000000046'
\set percentageDiscountID '79260000-0000-0000-0000-000000000019'
\set percentageDiscountUserID '79260000-0000-0000-0000-000000000027'
\set privatePriceWindowID '79260000-0000-0000-0000-000000000042'
\set privateTicketTypeID '79260000-0000-0000-0000-000000000041'
\set priceWindowAID '79260000-0000-0000-0000-000000000012'
\set priceWindowBID '79260000-0000-0000-0000-000000000013'
\set queuePriceWindowID '79260000-0000-0000-0000-000000000048'
\set queueTicketTypeID '79260000-0000-0000-0000-000000000047'
\set queueUserID '79260000-0000-0000-0000-000000000049'
\set redeemedPurchaseID '79260000-0000-0000-0000-000000000020'
\set redeemedUserID '79260000-0000-0000-0000-000000000030'
\set rejectedUserID '79260000-0000-0000-0000-000000000033'
\set soldOutEventID '79260000-0000-0000-0000-000000000004'
\set soldOutHolderUserID '79260000-0000-0000-0000-000000000031'
\set soldOutPriceWindowID '79260000-0000-0000-0000-000000000014'
\set soldOutPurchaseID '79260000-0000-0000-0000-000000000021'
\set soldOutTicketTypeID '79260000-0000-0000-0000-000000000008'
\set soldOutUserID '79260000-0000-0000-0000-000000000028'
\set ticketTypeAID '79260000-0000-0000-0000-000000000006'
\set ticketTypeBID '79260000-0000-0000-0000-000000000007'
\set truncationDiscountID '79260000-0000-0000-0000-000000000039'
\set truncationDiscountUserID '79260000-0000-0000-0000-000000000040'
\set truncationPriceWindowID '79260000-0000-0000-0000-000000000038'
\set truncationTicketTypeID '79260000-0000-0000-0000-000000000036'
\set unavailableDiscountUserID '79260000-0000-0000-0000-000000000024'
\set zeroPriceWindowID '79260000-0000-0000-0000-000000000044'
\set zeroTicketTypeID '79260000-0000-0000-0000-000000000043'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'attendeeUserID');
select fx_user(:'invalidDiscountUserID');
select fx_user(:'unavailableDiscountUserID');
select fx_user(:'exhaustedDiscountUserID');
select fx_user(:'fixedDiscountUserID');
select fx_user(:'percentageDiscountUserID');
select fx_user(:'truncationDiscountUserID');
select fx_user(:'soldOutUserID');
select fx_user(:'inactiveUserID');
select fx_user(:'redeemedUserID');
select fx_user(:'soldOutHolderUserID');
select fx_user(:'invitedUserID');
select fx_user(:'offerUserID');
select fx_user(:'queueUserID');
select fx_user(:'rejectedUserID');

-- Group
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('payment_recipient', jsonb_build_object(
        'provider', 'stripe',
        'recipient_id', 'acct_resolve_pricing',
        'seller_display_name', 'Resolve Pricing Fiscal Sponsor'
    )));

-- Events
select fx_event(:'mainEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));
select fx_event(:'soldOutEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));
select fx_event(:'inactiveEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'published_at', now(),
    'starts_at', now() + interval '2 days'
));

-- Ticket types
select fx_event_ticket_type(:'ticketTypeAID', :'mainEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketTypeBID', :'mainEventID', jsonb_build_object(
    'order', 2,
    'seats_total', 10,
    'title', 'VIP'
));
select fx_event_ticket_type(:'noActivePriceTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 3,
    'seats_total', 10
));
select fx_event_ticket_type(:'queueTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 4,
    'seats_total', 10
));
select fx_event_ticket_type(:'truncationTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 5,
    'seats_total', 10,
    'title', 'Truncated percent'
));
select fx_event_ticket_type(:'soldOutTicketTypeID', :'soldOutEventID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));
select fx_event_ticket_type(:'inactiveTicketTypeID', :'inactiveEventID', jsonb_build_object(
    'active', false,
    'seats_total', 10,
    'title', 'General admission'
));

-- Ticket types for direct-checkout pricing edge cases
select fx_event_ticket_type(:'ineffectiveDiscountTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 7,
    'seats_total', 10
));
select fx_event_ticket_type(:'privateTicketTypeID', :'mainEventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 5,
    'seats_total', 10,
    'title', 'Private pass'
));
select fx_event_ticket_type(:'zeroTicketTypeID', :'mainEventID', jsonb_build_object(
    'order', 6,
    'seats_total', 10
));

-- Price windows
select fx_event_ticket_price_window(:'priceWindowAID', :'ticketTypeAID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'priceWindowBID', :'ticketTypeBID', jsonb_build_object('amount_minor', 4000));
select fx_event_ticket_price_window(:'soldOutPriceWindowID', :'soldOutTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'inactivePriceWindowID', :'inactiveTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'ineffectiveDiscountPriceWindowID', :'ineffectiveDiscountTicketTypeID', jsonb_build_object('amount_minor', 1));
select fx_event_ticket_price_window(:'privatePriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'zeroPriceWindowID', :'zeroTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Price windows for edge cases
select fx_event_ticket_price_window(:'expiredPriceWindowID', :'noActivePriceTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', now() - interval '1 day',
    'starts_at', now() - interval '2 days'
));
select fx_event_ticket_price_window(:'truncationPriceWindowID', :'truncationTicketTypeID', jsonb_build_object('amount_minor', 99));
select fx_event_ticket_price_window(:'queuePriceWindowID', :'queueTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Discount codes
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    percentage,
    total_available,
    title
) values (
    :'freeDiscountID',
    true,
    2500,
    2,
    true,
    'FREEPASS',
    :'mainEventID',
    'fixed_amount',
    null,
    null,
    'Free pass'
), (
    :'inactiveDiscountID',
    false,
    500,
    1,
    true,
    'INACTIVE',
    :'mainEventID',
    'fixed_amount',
    null,
    null,
    'Inactive discount'
), (
    :'limitedDiscountID',
    true,
    500,
    5,
    true,
    'TOTAL1',
    :'mainEventID',
    'fixed_amount',
    null,
    1,
    'Limited discount'
), (
    :'percentageDiscountID',
    true,
    null,
    4,
    true,
    'VIP25',
    :'mainEventID',
    'percentage',
    25,
    null,
    'VIP 25'
), (
    :'truncationDiscountID',
    true,
    null,
    4,
    true,
    'PERCENT10',
    :'mainEventID',
    'percentage',
    10,
    null,
    'Percent 10'
);

-- Existing attendee
insert into event_attendee (event_id, user_id)
values (:'mainEventID', :'attendeeUserID');

-- Attendees with invitation lifecycle states checkout cannot confirm
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'mainEventID', :'invitedUserID', true, 'invitation-pending'),
    (:'mainEventID', :'rejectedUserID', true, 'invitation-rejected');

-- Existing purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
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
    fixtures.amount_minor,
    fixtures.currency_code,
    fixtures.discount_amount_minor,
    fixtures.discount_code,
    fixtures.event_discount_code_id::uuid,
    fixtures.event_id::uuid,
    fixtures.event_ticket_type_id::uuid,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_pricing',
    0,
    'stripe',
    'ch_' || fixtures.event_purchase_id,
    'cs_' || fixtures.event_purchase_id,
    'acct_pricing',
    'pi_' || fixtures.event_purchase_id,
    fixtures.amount_minor,
    '{"connected_account_id":"acct_pricing","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    fixtures.amount_minor,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'redeemedPurchaseID',
    2000,
    'USD',
    500,
    'TOTAL1',
    :'limitedDiscountID',
    :'mainEventID',
    :'ticketTypeAID',
    'completed',
    'General admission',
    :'redeemedUserID'
), (
    :'soldOutPurchaseID',
    2500,
    'USD',
    0,
    null,
    null,
    :'soldOutEventID',
    :'soldOutTicketTypeID',
    'refund-recovery-pending',
    'General admission',
    :'soldOutHolderUserID'
)) as fixtures (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
);

-- FIFO queue that blocks direct pricing for its tier
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'mainEventID', :'queueTicketTypeID', :'queueUserID');

insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'offerID',
    :'mainEventID',
    :'privateTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'offerUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject attendees that already have a seat
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000022'::uuid,
        null
    )$$,
    'OCG01',
    'user is already attending this event',
    'Should reject attendees that already have a seat'
);

-- Should reject users with a pending invitation
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000032'::uuid,
        null
    )$$,
    'OCG01',
    'user has a pending or rejected invitation for this event',
    'Should reject users with a pending invitation'
);

-- Should reject users with a rejected invitation
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000033'::uuid,
        null
    )$$,
    'OCG01',
    'user has a pending or rejected invitation for this event',
    'Should reject users with a rejected invitation'
);

-- Should reject sold out ticket types
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000004'::uuid,
        '79260000-0000-0000-0000-000000000008'::uuid,
        '79260000-0000-0000-0000-000000000028'::uuid,
        null
    )$$,
    'OCG01',
    'ticket type is sold out',
    'Should reject sold out ticket types'
);

-- Should reject missing ticket types
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000034'::uuid,
        '79260000-0000-0000-0000-000000000026'::uuid,
        null
    )$$,
    'OCG01',
    'ticket type not found',
    'Should reject missing ticket types'
);

-- Should reject inactive ticket types
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000005'::uuid,
        '79260000-0000-0000-0000-000000000009'::uuid,
        '79260000-0000-0000-0000-000000000029'::uuid,
        null
    )$$,
    'OCG01',
    'ticket type is not active',
    'Should reject inactive ticket types'
);

-- Should reject ticket types without an active price window
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000035'::uuid,
        '79260000-0000-0000-0000-000000000040'::uuid,
        null
    )$$,
    'OCG01',
    'ticket type does not have an active price window',
    'Should reject ticket types without an active price window'
);

-- Should reject invitation-only ticket identifiers from direct checkout
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000041'::uuid,
        '79260000-0000-0000-0000-000000000026'::uuid,
        null
    )$$,
    'OCG01',
    'ticket type is not available for direct checkout',
    'Should reject invitation-only ticket identifiers from direct checkout'
);

select results_eq(
    format(
        $$
        select final_amount_minor, ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'mainEventID',
        :'privateTicketTypeID',
        :'offerUserID',
        :'offerID'
    ),
    $$ values (2500::bigint, 'Private pass'::text) $$,
    'Should price the invitation-only tier assigned to an owned offer'
);

select throws_ok(
    format(
        $$
        select prepare_event_checkout_validate_and_resolve_pricing(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null,
            %L::uuid
        )
        $$,
        :'mainEventID',
        :'privateTicketTypeID',
        :'offerUserID',
        :'missingTicketTypeID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject pricing without the exact owned offer'
);

-- Should reject ineffective discount codes on intrinsically free tickets
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000043'::uuid,
        '79260000-0000-0000-0000-000000000027'::uuid,
        'VIP25'
    )$$,
    'OCG01',
    'discount codes cannot be applied to free tickets',
    'Should reject ineffective discount codes on intrinsically free tickets'
);

-- Should reject percentage discounts below one minor unit
select throws_ok(
    format(
        $$
            select prepare_event_checkout_validate_and_resolve_pricing(
                %L::uuid,
                %L::uuid,
                %L::uuid,
                'VIP25'
            )
        $$,
        :'mainEventID',
        :'ineffectiveDiscountTicketTypeID',
        :'percentageDiscountUserID'
    ),
    'OCG01',
    'discount code does not reduce ticket price',
    'Should reject percentage discounts below one minor unit'
);

-- Should reject direct pricing while a tier queue remains blocked
select throws_ok(
    format(
        $$select prepare_event_checkout_validate_and_resolve_pricing(
            %L::uuid,
            %L::uuid,
            %L::uuid,
            null
        )$$,
        :'mainEventID',
        :'queueTicketTypeID',
        :'fixedDiscountUserID'
    ),
    'OCG01',
    'ticket type has queued users',
    'Should reject direct pricing while a tier queue remains blocked'
);

-- Should reject unknown discount codes
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000023'::uuid,
        'missing'
    )$$,
    'OCG01',
    'discount code not found',
    'Should reject unknown discount codes'
);

-- Should reject unavailable discount codes
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000024'::uuid,
        'INACTIVE'
    )$$,
    'OCG01',
    'discount code is not available',
    'Should reject unavailable discount codes'
);

-- Should reject discounts whose total availability is exhausted
select throws_ok(
    $$select prepare_event_checkout_validate_and_resolve_pricing(
        '79260000-0000-0000-0000-000000000003'::uuid,
        '79260000-0000-0000-0000-000000000006'::uuid,
        '79260000-0000-0000-0000-000000000025'::uuid,
        'TOTAL1'
    )$$,
    'OCG01',
    'discount code is no longer available',
    'Should reject discounts whose total availability is exhausted'
);

-- Should compute pricing for a valid fixed-amount discount
select results_eq(
    $$
        select
            discount_amount_minor::text,
            event_discount_code_id::text,
            final_amount_minor::text,
            ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            '79260000-0000-0000-0000-000000000003'::uuid,
            '79260000-0000-0000-0000-000000000006'::uuid,
            '79260000-0000-0000-0000-000000000026'::uuid,
            'FREEPASS'
        )
    $$,
    $$ values (
        '2500'::text,
        '79260000-0000-0000-0000-000000000016'::text,
        '0'::text,
        'General admission'::text
    ) $$,
    'Should compute pricing for a valid fixed-amount discount'
);

-- Should compute pricing for a valid percentage discount
select results_eq(
    $$
        select
            discount_amount_minor::text,
            event_discount_code_id::text,
            final_amount_minor::text,
            ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            '79260000-0000-0000-0000-000000000003'::uuid,
            '79260000-0000-0000-0000-000000000007'::uuid,
            '79260000-0000-0000-0000-000000000027'::uuid,
            'VIP25'
        )
    $$,
    $$ values (
        '1000'::text,
        '79260000-0000-0000-0000-000000000019'::text,
        '3000'::text,
        'VIP'::text
    ) $$,
    'Should compute pricing for a valid percentage discount'
);

-- Should truncate percentage discounts to integer minor units
select results_eq(
    $$
        select
            discount_amount_minor::text,
            event_discount_code_id::text,
            final_amount_minor::text,
            ticket_title
        from prepare_event_checkout_validate_and_resolve_pricing(
            '79260000-0000-0000-0000-000000000003'::uuid,
            '79260000-0000-0000-0000-000000000036'::uuid,
            '79260000-0000-0000-0000-000000000040'::uuid,
            'PERCENT10'
        )
    $$,
    $$ values (
        '9'::text,
        '79260000-0000-0000-0000-000000000039'::text,
        '90'::text,
        'Truncated percent'::text
    ) $$,
    'Should truncate percentage discounts to integer minor units'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
