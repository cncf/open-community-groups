-- Tests reconciling provider checkout sessions with event purchases.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(43);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID '79000000-0000-0000-0000-000000000004'
\set activeOfferRefundOfferID '79000000-0000-0000-0000-000000000116'
\set activeOfferRefundPurchaseID '79000000-0000-0000-0000-000000000117'
\set activeOfferRefundUserID '79000000-0000-0000-0000-000000000118'
\set activePriceWindowID '79000000-0000-0000-0000-000000000010'
\set activeTicketTypeID '79000000-0000-0000-0000-000000000006'
\set canceledEventID '79000000-0000-0000-0000-000000000005'
\set canceledPriceWindowID '79000000-0000-0000-0000-000000000011'
\set canceledTicketTypeID '79000000-0000-0000-0000-000000000007'
\set communityID '79000000-0000-0000-0000-000000000001'
\set discountCodeID '79000000-0000-0000-0000-000000000002'
\set eventCategoryID '79000000-0000-0000-0000-000000000003'
\set groupCategoryID '79000000-0000-0000-0000-000000000008'
\set groupID '79000000-0000-0000-0000-000000000009'
\set linkedOfferID '79000000-0000-0000-0000-000000000038'
\set linkedLatePurchaseID '79000000-0000-0000-0000-00000000003e'
\set linkedPurchaseID '79000000-0000-0000-0000-000000000039'
\set linkedUserID '79000000-0000-0000-0000-00000000003a'
\set dueOfferID '79000000-0000-0000-0000-00000000003b'
\set duePurchaseID '79000000-0000-0000-0000-00000000003c'
\set dueUserID '79000000-0000-0000-0000-00000000003d'
\set purchaseCanceledID '79000000-0000-0000-0000-000000000014'
\set purchaseCompleteID '79000000-0000-0000-0000-000000000012'
\set purchaseConfirmedID '79000000-0000-0000-0000-000000000028'
\set purchaseDoneID '79000000-0000-0000-0000-000000000016'
\set purchaseExpiredActiveHoldID '79000000-0000-0000-0000-000000000026'
\set purchaseExpiredID '79000000-0000-0000-0000-000000000013'
\set purchaseInvitedID '79000000-0000-0000-0000-000000000027'
\set purchaseMissingRefID '79000000-0000-0000-0000-000000000015'
\set purchaseOpenUntilStartID '79000000-0000-0000-0000-000000000031'
\set purchaseRecoveryID '79000000-0000-0000-0000-000000000035'
\set purchaseRecoveryReplacementID '79000000-0000-0000-0000-000000000036'
\set purchaseStartedID '79000000-0000-0000-0000-000000000022'
\set raceEventID '79000000-0000-0000-0000-000000000110'
\set racePriceWindowID '79000000-0000-0000-0000-000000000112'
\set racePurchaseID '79000000-0000-0000-0000-000000000113'
\set raceQueueUserID '79000000-0000-0000-0000-000000000115'
\set raceTicketTypeID '79000000-0000-0000-0000-000000000111'
\set raceUserID '79000000-0000-0000-0000-000000000114'
\set registrationQuestionID '79000000-0000-0000-0000-000000000101'
\set openUntilStartEventID '79000000-0000-0000-0000-000000000032'
\set openUntilStartTicketTypeID '79000000-0000-0000-0000-000000000033'
\set startedEventID '79000000-0000-0000-0000-000000000023'
\set startedTicketTypeID '79000000-0000-0000-0000-000000000024'
\set user1ID '79000000-0000-0000-0000-000000000017'
\set user2ID '79000000-0000-0000-0000-000000000018'
\set user3ID '79000000-0000-0000-0000-000000000019'
\set user4ID '79000000-0000-0000-0000-000000000020'
\set user5ID '79000000-0000-0000-0000-000000000021'
\set user6ID '79000000-0000-0000-0000-000000000025'
\set user7ID '79000000-0000-0000-0000-000000000029'
\set user8ID '79000000-0000-0000-0000-000000000030'
\set user9ID '79000000-0000-0000-0000-000000000034'
\set user10ID '79000000-0000-0000-0000-000000000037'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'complete-community',
    'Complete Community',
    'Test',
    'https://e/banner-mobile.png',
    'https://e/banner.png',
    'https://e/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Tech');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (user_id, auth_hash, email, email_verified, username)
values
    (
        :'activeOfferRefundUserID',
        'hash-active-offer-refund',
        'active-offer-refund@example.com',
        true,
        'active-offer-refund'
    ),
    (:'user1ID', 'hash-1', 'user1@example.com', true, 'buyer-1'),
    (:'user2ID', 'hash-2', 'user2@example.com', true, 'buyer-2'),
    (:'user3ID', 'hash-3', 'user3@example.com', true, 'buyer-3'),
    (:'user4ID', 'hash-4', 'user4@example.com', true, 'buyer-4'),
    (:'user5ID', 'hash-5', 'user5@example.com', true, 'buyer-5'),
    (:'user6ID', 'hash-6', 'user6@example.com', true, 'buyer-6'),
    (:'user7ID', 'hash-7', 'user7@example.com', true, 'buyer-7'),
    (:'user8ID', 'hash-8', 'user8@example.com', true, 'buyer-8'),
    (:'user9ID', 'hash-9', 'user9@example.com', true, 'buyer-9'),
    (:'user10ID', 'hash-10', 'user10@example.com', true, 'buyer-10'),
    (:'dueUserID', 'hash-due', 'due@example.com', true, 'due-buyer'),
    (:'linkedUserID', 'hash-linked', 'linked@example.com', true, 'linked-buyer'),
    (:'raceQueueUserID', 'hash-race-queue', 'race-queue@example.com', true, 'race-queue'),
    (:'raceUserID', 'hash-race', 'race@example.com', true, 'race-buyer');

-- Group
insert into "group" (
    community_id,
    group_category_id,
    group_id,
    name,
    payment_recipient,
    slug
) values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Complete Group',
    '{"provider":"stripe","recipient_id":"acct_complete","seller_display_name":"Complete Fiscal Sponsor"}'::jsonb,
    'complete-group'
);

-- Events
insert into event (
    canceled,
    event_id,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    slug,
    description,
    timezone,
    ends_at,
    starts_at,
    published,
    published_at,
    registration_questions,
    registration_starts_at
) values (
    -- Event with pending registration answers created during checkout
    false,
    :'activeEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Active Event',
    'active-event',
    'Test event',
    'UTC',
    null,
    now() + interval '1 day',
    true,
    now(),
    jsonb_build_array(jsonb_build_object(
        'id', :'registrationQuestionID',
        'kind', 'free-text',
        'options', jsonb_build_array(),
        'prompt', 'Note',
        'required', true
    )),
    null
), (
    false,
    :'startedEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Started Event',
    'started-event',
    'Test event',
    'UTC',
    null,
    now() - interval '1 hour',
    true,
    now(),
    '[]'::jsonb,
    null
), (
    false,
    :'openUntilStartEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Open Until Start Event',
    'open-until-start-event',
    'Test event',
    'UTC',
    now() + interval '1 hour',
    now() - interval '1 hour',
    true,
    now(),
    '[]'::jsonb,
    now() - interval '2 hours'
), (
    true,
    :'canceledEventID',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Canceled Event',
    'canceled-event',
    'Test event',
    'UTC',
    null,
    now() + interval '1 day',
    false,
    null,
    '[]'::jsonb,
    null
);

-- Payment-race event whose only seat remains reserved during refund handoff
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Late payment capacity race',
    :'eventCategoryID',
    :'raceEventID',
    'in-person',
    :'groupID',
    'Late Payment Capacity Race',
    'USD',
    true,
    'late-payment-capacity-race',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Ticket types
insert into event_ticket_type (event_ticket_type_id, event_id, "order", seats_total, title)
values
    (:'activeTicketTypeID', :'activeEventID', 1, 10, 'General admission'),
    (:'canceledTicketTypeID', :'canceledEventID', 1, 10, 'General admission'),
    (:'openUntilStartTicketTypeID', :'openUntilStartEventID', 1, 10, 'General admission'),
    (:'raceTicketTypeID', :'raceEventID', 1, 1, 'Race admission'),
    (:'startedTicketTypeID', :'startedEventID', 1, 10, 'General admission');

-- Ticket price windows
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id
) values
    (:'activePriceWindowID', 2500, :'activeTicketTypeID'),
    (:'canceledPriceWindowID', 2500, :'canceledTicketTypeID'),
    (:'racePriceWindowID', 2500, :'raceTicketTypeID');

-- Discount code used by the expired purchase
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
    :'activeEventID',
    'fixed_amount',
    'Save 5'
);

-- Purchases
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id,

    charge_model,
    connected_seller_id,
    final_platform_fee_amount_minor,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    provider_charge_id,
    provider_object_account_id,
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
    fixtures.hold_expires_at,
    fixtures.payment_provider_id,
    coalesce(
        fixtures.provider_checkout_session_id,
        case
            when fixtures.status in (
                'completed',
                'refund-recovery-pending'
            ) then 'cs_' || fixtures.event_purchase_id::text
        end
    ),
    fixtures.provider_payment_reference,
    fixtures.status,
    fixtures.ticket_title,
    fixtures.user_id::uuid,

    'direct-charge',
    'acct_complete',
    case
        when fixtures.status in (
            'completed',
            'refund-recovery-pending'
        ) then 0
    end,
    case
        when fixtures.event_purchase_id::uuid = :'purchaseConfirmedID'::uuid then 250
        else 0
    end,
    case
        when fixtures.event_purchase_id::uuid = :'purchaseConfirmedID'::uuid then 62
        when fixtures.event_purchase_id::uuid = :'purchaseExpiredID'::uuid then 50
        else 0
    end,
    case
        when fixtures.status in (
            'completed',
            'refund-recovery-pending'
        ) then 'ch_' || fixtures.event_purchase_id::text
    end,
    'acct_complete',
    case
        when fixtures.status in (
            'completed',
            'refund-recovery-pending'
        ) then fixtures.amount_minor
    end,
    '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    case
        when fixtures.status in (
            'completed',
            'refund-recovery-pending'
        ) then fixtures.amount_minor
    end,
    case
        when fixtures.status in (
            'completed',
            'refund-recovery-pending'
        ) then 0
    end,
    'inclusive',
    'manual',
    'professional-event-admission',
    '{}'::jsonb
from (values (
    :'purchaseCompleteID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_complete',
    null,
    'pending',
    'General admission',
    :'user1ID'
), (
    :'purchaseExpiredID',
    2000,
    'USD',
    500,
    'SAVE5',
    :'discountCodeID',
    :'activeEventID',
    :'activeTicketTypeID',
    now() - interval '15 minutes',
    'stripe',
    'cs_expired',
    'pi_expired',
    'pending',
    'General admission',
    :'user2ID'
), (
    :'purchaseExpiredActiveHoldID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_expired_active_hold',
    'pi_expired_active_hold',
    'expired',
    'General admission',
    :'user5ID'
), (
    :'purchaseCanceledID',
    2500,
    'USD',
    0,
    null,
    null,
    :'canceledEventID',
    :'canceledTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_canceled',
    'pi_canceled',
    'pending',
    'General admission',
    :'user3ID'
), (
    :'purchaseMissingRefID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() - interval '15 minutes',
    'stripe',
    'cs_missing_ref',
    null,
    'pending',
    'General admission',
    :'user4ID'
), (
    :'purchaseStartedID',
    2500,
    'USD',
    0,
    null,
    null,
    :'startedEventID',
    :'startedTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_started',
    null,
    'pending',
    'General admission',
    :'user6ID'
), (
    :'purchaseOpenUntilStartID',
    2500,
    'USD',
    0,
    null,
    null,
    :'openUntilStartEventID',
    :'openUntilStartTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_open_until_start',
    null,
    'pending',
    'General admission',
    :'user9ID'
), (
    :'purchaseRecoveryID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    null,
    'stripe',
    null,
    'pi_recovery_original',
    'refund-recovery-pending',
    'General admission',
    :'user10ID'
), (
    :'purchaseRecoveryReplacementID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_recovery_replacement',
    null,
    'pending',
    'General admission',
    :'user10ID'
), (
    :'purchaseInvitedID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_invited',
    'pi_invited',
    'pending',
    'General admission',
    :'user7ID'
), (
    :'purchaseConfirmedID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    now() + interval '15 minutes',
    'stripe',
    'cs_confirmed',
    'pi_confirmed',
    'pending',
    'General admission',
    :'user8ID'
), (
    :'purchaseDoneID',
    2500,
    'USD',
    0,
    null,
    null,
    :'activeEventID',
    :'activeTicketTypeID',
    null,
    'stripe',
    'cs_done',
    'pi_done',
    'completed',
    'General admission',
    :'user5ID'
)) as fixtures (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_payment_reference,
    status,
    ticket_title,
    user_id
);

-- Expired provider checkout whose payment must reserve the only race-event seat
insert into event_purchase (
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
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
    'acct_complete',
    'USD',
    :'raceEventID',
    :'racePurchaseID',
    :'raceTicketTypeID',
    current_timestamp - interval '15 minutes',
    'stripe',
    'cs_capacity_race',
    'acct_complete',
    'pi_capacity_race',
    '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'Race admission',
    :'raceUserID',
    '{}'::jsonb
);

-- Expired direct checkout that paid after the user received an offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values (
    :'activeOfferRefundPurchaseID',
    2500,
    'direct-charge',
    'acct_complete',
    'USD',
    :'activeEventID',
    :'activeTicketTypeID',
    current_timestamp - interval '15 minutes',
    'stripe',
    'cs_expired_active_offer',
    'acct_complete',
    'pi_expired_active_offer',
    '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'expired',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'activeOfferRefundUserID',
    '{}'::jsonb
);

-- Active organizer offer created after the direct checkout expired
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'activeOfferRefundOfferID',
    :'activeEventID',
    :'activeTicketTypeID',
    current_timestamp + interval '1 day',
    'organizer_invitation',
    'pending',
    :'activeOfferRefundUserID'
);

-- Queue head that must not be promoted ahead of the paid refund reservation
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'raceEventID', :'raceTicketTypeID', :'raceQueueUserID');

-- Active and deadline-expired checkout offers for provider completion
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id,

    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    ticket_title
) values
    (
        :'linkedOfferID',
        current_timestamp,
        :'activeEventID',
        :'activeTicketTypeID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'checkout_pending',
        :'linkedUserID',

        2500,
        'USD',
        0,
        null,
        null,
        'General admission'
    ),
    (
        :'dueOfferID',
        current_timestamp - interval '2 hours',
        :'activeEventID',
        :'activeTicketTypeID',
        current_timestamp - interval '1 hour',
        'waitlist',
        'checkout_pending',
        :'dueUserID',

        2500,
        'USD',
        0,
        null,
        null,
        'General admission'
    );

-- Purchases linked to the active and deadline-expired offers
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
    provider_checkout_session_id,
    provider_object_account_id,
    provider_payment_reference,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot
) values
    (
        :'linkedOfferID',
        2500,
        'direct-charge',
        'acct_complete',
        'USD',
        0,
        :'activeEventID',
        :'linkedPurchaseID',
        :'activeTicketTypeID',
        current_timestamp + interval '15 minutes',
        'stripe',
        'cs_offer_complete',
        'acct_complete',
        null,
        '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'General admission',
        :'linkedUserID',
        '{}'::jsonb
    ),
    (
        :'dueOfferID',
        2500,
        'direct-charge',
        'acct_complete',
        'USD',
        0,
        :'activeEventID',
        :'duePurchaseID',
        :'activeTicketTypeID',
        current_timestamp + interval '15 minutes',
        'stripe',
        'cs_offer_due',
        'acct_complete',
        'pi_offer_due',
        '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
        'pending',
        'inclusive',
        'manual',
        'professional-event-admission',
        'General admission',
        :'dueUserID',
        '{}'::jsonb
    );

-- Canceled first checkout that can pay after its replacement completes
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    created_at,
    currency_code,
    discount_amount_minor,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    payment_provider_id,
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
    :'linkedOfferID',
    2500,
    'direct-charge',
    'acct_complete',
    current_timestamp - interval '1 hour',
    'USD',
    0,
    :'activeEventID',
    :'linkedLatePurchaseID',
    :'activeTicketTypeID',
    current_timestamp - interval '45 minutes',
    'stripe',
    'cs_offer_late',
    'acct_complete',
    '{"connected_account_id":"acct_complete","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'expired',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'linkedUserID',
    '{}'::jsonb
);

-- Pending attendee row with registration answers created during checkout
insert into event_attendee (event_id, user_id, registration_answers, status)
values
    (
        :'activeEventID',
        :'user1ID',
        jsonb_build_object(
            'answers',
            jsonb_build_array(jsonb_build_object(
                'question_id', :'registrationQuestionID',
                'value', 'Paid checkout answer'
            ))
        ),
        'registration-questions-pending'
    ),
    (
        :'activeEventID',
        :'user2ID',
        jsonb_build_object(
            'answers',
            jsonb_build_array(jsonb_build_object(
                'question_id', :'registrationQuestionID',
                'value', 'Expired checkout answer'
            ))
        ),
        'registration-questions-pending'
    ),
    (
        :'canceledEventID',
        :'user3ID',
        null,
        'registration-questions-pending'
    ),
    (
        :'startedEventID',
        :'user6ID',
        null,
        'registration-questions-pending'
    );

-- Attendee lifecycle rows that exercise the completion confirmation guard
insert into event_attendee (event_id, user_id, manually_invited, status)
values
    (:'activeEventID', :'user7ID', true, 'invitation-pending'),
    (:'activeEventID', :'user8ID', false, 'confirmed');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return noop when there is no matching checkout session
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_missing', 'pi_missing',
        'ch_missing', 2500, 0, null
    )::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should return noop when there is no matching checkout session'
);

-- Should reserve capacity before reconciling a late paid checkout
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_capacity_race',
        'pi_capacity_race',
        'ch_capacity_race',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should reserve capacity before reconciling a late paid checkout'
);

-- Should keep the queue head waiting while the late payment awaits refund
select results_eq(
    format(
        $$
            select
                ep.status,
                exists (
                    select 1
                    from event_waitlist ew
                    where ew.event_id = %L::uuid
                    and ew.event_ticket_type_id = %L::uuid
                    and ew.user_id = %L::uuid
                ),
                not exists (
                    select 1
                    from admission_offer ao
                    where ao.event_id = %L::uuid
                    and ao.user_id = %L::uuid
                )
            from event_purchase ep
            where ep.event_purchase_id = %L::uuid
        $$,
        :'raceEventID',
        :'raceTicketTypeID',
        :'raceQueueUserID',
        :'raceEventID',
        :'raceQueueUserID',
        :'racePurchaseID'
    ),
    $$ values ('refund-pending'::text, true, true) $$,
    'Should keep the queue head waiting while the late payment awaits refund'
);

-- Should return noop for expired purchases whose hold has not expired locally
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_expired_active_hold',
        'pi_expired_active_hold', 'ch_expired_active_hold', 2500, 0, null
    )::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should return noop for expired purchases whose hold has not expired locally'
);

-- Should complete a valid pending checkout session
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_complete', 'pi_complete',
        'ch_complete', 2500, 0, null
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'activeEventID'::uuid,
        'outcome', 'completed',
        'user_id', :'user1ID'::uuid
    ),
    'Should complete a valid pending checkout session'
);

-- Should persist the completed purchase fields and add the attendee
select results_eq(
    $$
        select
            (
                select completed_at is not null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select provider_payment_reference
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000012'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000017'::uuid
            ),
            (
                select manually_invited
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000017'::uuid
            ),
            (
                select status
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000017'::uuid
            ),
            (
                select registration_answers
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000017'::uuid
            )
    $$,
    $$
        values (
            true,
            true,
            'pi_complete'::text,
            'completed'::text,
            1::int,
            false,
            'confirmed'::text,
            '{"answers": [{"question_id": "79000000-0000-0000-0000-000000000101", "value": "Paid checkout answer"}]}'::jsonb
        )
    $$,
    'Should persist the completed purchase fields and confirm a non-manually invited attendee'
);

-- Should complete an active offer-linked checkout
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_offer_complete',
        'pi_offer_complete',
        'ch_offer_complete',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'activeEventID'::uuid,
        'outcome', 'completed',
        'user_id', :'linkedUserID'::uuid
    ),
    'Should complete an active offer-linked checkout'
);

select results_eq(
    format(
        $$
            select
                ao.status,
                ep.status,
                ea.manually_invited,
                ea.status
            from admission_offer ao
            join event_purchase ep using (admission_offer_id)
            join event_attendee ea
                on ea.event_id = ep.event_id
                and ea.user_id = ep.user_id
            where ao.admission_offer_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'linkedOfferID',
        :'linkedPurchaseID'
    ),
    $$ values ('completed'::text, 'completed'::text, true, 'confirmed'::text) $$,
    'Should complete the linked organizer offer with invitation provenance'
);

-- Capture allocated seats before reconciling the late payment
select get_event_ticket_type_allocated_seat_count(
    :'activeEventID',
    :'activeTicketTypeID'
) as linked_allocated_before \gset

-- Should queue a late offer payment after its replacement completed
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_offer_late',
        'pi_offer_late',
        'ch_offer_late',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should queue a late offer payment after its replacement completed'
);

-- Should preserve the replacement while refunding the late payment
select results_eq(
    format(
        $$
            select
                late_purchase.status,
                replacement.status,
                (
                    select count(*)::int
                    from event_purchase_refund epr
                    where epr.event_purchase_id = late_purchase.event_purchase_id
                ),
                get_event_ticket_type_allocated_seat_count(
                    late_purchase.event_id,
                    late_purchase.event_ticket_type_id
                ) = %L::int
            from event_purchase late_purchase
            join event_purchase replacement
                on replacement.event_purchase_id = %L::uuid
            where late_purchase.event_purchase_id = %L::uuid
        $$,
        :'linked_allocated_before',
        :'linkedPurchaseID',
        :'linkedLatePurchaseID'
    ),
    $$ values ('refund-pending'::text, 'completed'::text, 1::int, true) $$,
    'Should preserve the replacement and count one seat while refunding the late payment'
);

-- Should refund provider success after the linked offer deadline
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_offer_due',
        'pi_offer_due',
        'ch_offer_due',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should refund provider success after the linked offer deadline'
);

select results_eq(
    format(
        $$
            select
                ao.status,
                ep.status,
                epr.kind
            from admission_offer ao
            join event_purchase ep using (admission_offer_id)
            join event_purchase_refund epr using (event_purchase_id)
            where ao.admission_offer_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'dueOfferID',
        :'duePurchaseID'
    ),
    $$ values (
        'expired'::text,
        'refund-pending'::text,
        'automatic-unfulfillable-checkout'::text
    ) $$,
    'Should keep the expired offer terminal and queue its purchase refund'
);

-- Should require refund for expired local holds
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_expired', 'pi_expired',
        'ch_expired', 2000, 0, null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should require refund for expired local holds'
);

-- Should persist the refund-pending purchase fields and restore discount availability
select results_eq(
    $$
        select
            (select hold_expires_at is null from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select provider_payment_reference from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select status from event_purchase where event_purchase_id = '79000000-0000-0000-0000-000000000013'::uuid),
            (select available from event_discount_code where event_discount_code_id = '79000000-0000-0000-0000-000000000002'::uuid),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000018'::uuid
            )
    $$,
    $$ values (true, 'pi_expired'::text, 'refund-pending'::text, 1::int, 0::int) $$,
    'Should persist the refund-pending purchase fields, release registration hold, and restore discount availability'
);

-- Should keep requiring refund for refund-pending purchases after the refund handoff
select lives_ok(
    $$select attach_application_fee_to_event_purchase(
        'stripe', 'acct_complete', 'ch_expired', 'fee_expired', 50
    )$$,
    'Should attach a delayed application fee to a refund-pending purchase'
);

-- Claim and complete the fee adjustment before another Checkout replay arrives
select lives_ok(
    $$
        with claim as (
            select claim_event_purchase_application_fee_adjustment('stripe') as payload
        )
        select record_event_purchase_application_fee_adjustment_succeeded(
            (payload->>'event_purchase_application_fee_adjustment_id')::uuid,
            (payload->>'claim_id')::uuid,
            'fr_expired'
        )
        from claim
    $$,
    'Should complete financial reconciliation before Checkout replay'
);

-- Replay the refund-pending Checkout after financial work completed
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_expired', 'pi_expired',
        'ch_expired', 2000, 0, null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should keep requiring refund for refund-pending purchases after the refund handoff'
);

select results_eq(
    format($$
        select
            ep.provider_application_fee_id,
            ep.financially_reconciled_at is not null,
            count(epafa.*)::int
        from event_purchase ep
        left join event_purchase_application_fee_adjustment epafa
            using (event_purchase_id)
        where ep.event_purchase_id = %L::uuid
        group by ep.event_purchase_id
    $$, :'purchaseExpiredID'),
    $$ values ('fee_expired'::text, true, 1::int) $$,
    'Should preserve completed financial state and one adjustment across replay'
);

select throws_ok(
    $$select reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_expired', 'pi_expired',
        'ch_expired', 2000, 0, 'fee_conflicting'
    )$$,
    'provider application fee does not match the purchase',
    'Should reject a conflicting application fee during replay'
);

select is(
    (
        select provider_application_fee_id
        from event_purchase
        where event_purchase_id = :'purchaseExpiredID'::uuid
    ),
    'fee_expired',
    'Should preserve the attached application fee after a conflicting replay'
);

-- Should not restore discount availability twice for already expired purchases
select is(
    (
        select available
        from event_discount_code
        where event_discount_code_id = :'discountCodeID'::uuid
    ),
    1,
    'Should not restore discount availability twice for already expired purchases'
);

-- Should require refund when the event can no longer be fulfilled
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_canceled', 'pi_canceled',
        'ch_canceled', 2500, 0, null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should require refund when the event can no longer be fulfilled'
);

-- Should require refund when recovery won before a replacement checkout payment
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_recovery_replacement',
        'pi_recovery_replacement',
        'ch_recovery_replacement',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should require refund when recovery won before a replacement checkout payment'
);

-- Should preserve recovery and hand the paid replacement to refund processing
select results_eq(
    format($$
        select
            recovery.status,
            replacement.hold_expires_at is null,
            replacement.provider_payment_reference,
            replacement.status
        from event_purchase recovery
        join event_purchase replacement
            on replacement.event_id = recovery.event_id
            and replacement.user_id = recovery.user_id
        where recovery.event_purchase_id = %L::uuid
        and replacement.event_purchase_id = %L::uuid
    $$, :'purchaseRecoveryID', :'purchaseRecoveryReplacementID'),
    $$ values (
        'refund-recovery-pending'::text,
        true,
        'pi_recovery_replacement'::text,
        'refund-pending'::text
    ) $$,
    'Should preserve recovery and hand the paid replacement to refund processing'
);

-- Should require refund when the event has already started
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_started', 'pi_started',
        'ch_started', 2500, 0, null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should require refund when the event has already started'
);

-- Should complete active holds after an open-only registration window reaches the event start
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_open_until_start',
        'pi_open_until_start',
        'ch_open_until_start',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'openUntilStartEventID'::uuid,
        'outcome', 'completed',
        'user_id', :'user9ID'::uuid
    ),
    'Should complete active holds after an open-only registration window reaches the event start'
);

-- Should persist the open-only registration window completion
select results_eq(
    $$
        select
            (
                select completed_at is not null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000031'::uuid
            ),
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000031'::uuid
            ),
            (
                select provider_payment_reference
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000031'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000031'::uuid
            ),
            (
                select status
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000032'::uuid
                and user_id = '79000000-0000-0000-0000-000000000034'::uuid
            )
    $$,
    $$ values (true, true, 'pi_open_until_start'::text, 'completed'::text, 'confirmed'::text) $$,
    'Should persist the completed open-only hold purchase and attendee row'
);

-- Should persist the canceled purchase fields when refunding
select results_eq(
    $$
        select
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000014'::uuid
            ),
            (
                select provider_payment_reference
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000014'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000014'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000005'::uuid
                and user_id = '79000000-0000-0000-0000-000000000019'::uuid
            )
    $$,
    $$ values (true, 'pi_canceled'::text, 'refund-pending'::text, 0::int) $$,
    'Should persist the canceled purchase fields and release registration hold when refunding'
);

-- Should persist the started purchase fields when refunding
select results_eq(
    $$
        select
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000022'::uuid
            ),
            (
                select provider_payment_reference
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000022'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000022'::uuid
            ),
            (
                select count(*)::int
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000023'::uuid
                and user_id = '79000000-0000-0000-0000-000000000025'::uuid
            )
    $$,
    $$ values (true, 'pi_started'::text, 'refund-pending'::text, 0::int) $$,
    'Should persist the started purchase fields and release registration hold when refunding'
);

-- Should reject refund-required paths without a provider payment reference
select throws_ok(
    $$select reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_missing_ref', null,
        'ch_missing_ref', 2500, 0, null
    )$$,
    'direct-charge payment references are required',
    'Should reject refund-required paths without a provider payment reference'
);

-- Should require refund when the attendee row cannot be confirmed
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_invited', 'pi_invited',
        'ch_invited', 2500, 0, null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should require refund when the attendee row cannot be confirmed'
);

-- Should persist the refunding purchase fields and keep the invitation row
select results_eq(
    $$
        select
            (
                select hold_expires_at is null
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000027'::uuid
            ),
            (
                select status
                from event_purchase
                where event_purchase_id = '79000000-0000-0000-0000-000000000027'::uuid
            ),
            (
                select status
                from event_attendee
                where event_id = '79000000-0000-0000-0000-000000000004'::uuid
                and user_id = '79000000-0000-0000-0000-000000000029'::uuid
            )
    $$,
    $$ values (true, 'refund-pending'::text, 'invitation-pending'::text) $$,
    'Should persist the refunding purchase fields and keep the invitation row'
);

-- Should persist every automatic refund handoff for worker processing
select results_eq(
    format($$
        select
            count(*)::int,
            bool_and(epr.amount_minor = ep.amount_minor),
            bool_and(epr.currency_code = ep.currency_code),
            bool_and(epr.idempotency_key = 'event-purchase-refund-' || ep.event_purchase_id),
            bool_and(epr.kind = 'automatic-unfulfillable-checkout'),
            bool_and(epr.payment_provider_id = 'stripe'),
            bool_and(epr.status = 'provider-pending')
        from event_purchase ep
        join event_purchase_refund epr using (event_purchase_id)
        where ep.event_purchase_id in (
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
    $$,
        :'purchaseCanceledID',
        :'purchaseExpiredID',
        :'purchaseInvitedID',
        :'purchaseRecoveryReplacementID',
        :'purchaseStartedID'
    ),
    $$ values (5, true, true, true, true, true, true) $$,
    'Should persist every automatic refund handoff for worker processing'
);

-- Should keep one durable refund after replaying the same checkout webhook
select is(
    (
        select count(*)::int
        from event_purchase_refund
        where event_purchase_id = :'purchaseExpiredID'
    ),
    1,
    'Should keep one durable refund after replaying the same checkout webhook'
);

-- Should complete checkout sessions for already confirmed attendees
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_confirmed', 'pi_confirmed',
        'ch_confirmed', 2500, 0, null
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'activeEventID'::uuid,
        'outcome', 'completed',
        'user_id', :'user8ID'::uuid
    ),
    'Should complete checkout sessions for already confirmed attendees'
);

-- Should persist authoritative amounts without waiting for the asynchronous fee
select results_eq(
    $$
        select
            financially_reconciled_at is not null,
            provider_application_fee_id,
            provider_charge_id,
            status
        from event_purchase
        where provider_checkout_session_id = 'cs_confirmed'
    $$,
    $$ values (true, null::text, 'ch_confirmed'::text, 'completed'::text) $$,
    'Should fulfill a paid checkout before its application fee is available'
);

-- Should reject an application fee whose amount does not match Checkout
select throws_ok(
    $$select attach_application_fee_to_event_purchase(
        'stripe', 'acct_complete', 'ch_confirmed', 'fee_confirmed', 61
    )$$,
    'application fee amount does not match the purchase',
    'Should reject an application fee with the wrong amount'
);

-- Should attach the delayed provider application fee through its charge scope
select lives_ok(
    $$select attach_application_fee_to_event_purchase(
        'stripe', 'acct_complete', 'ch_confirmed', 'fee_confirmed', 62
    )$$,
    'Should attach the asynchronously created application fee'
);

-- Should persist the application fee on its completed purchase
select is(
    (
        select provider_application_fee_id
        from event_purchase
        where provider_checkout_session_id = 'cs_confirmed'
    ),
    'fee_confirmed',
    'Should persist the asynchronously created application fee'
);

-- Should idempotently accept the same application fee delivery again
select lives_ok(
    $$select attach_application_fee_to_event_purchase(
        'stripe', 'acct_complete', 'ch_confirmed', 'fee_confirmed', 62
    )$$,
    'Should accept an application-fee webhook replay'
);

-- Should noop for already completed purchases
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe', 'acct_complete', 'cs_done', 'pi_done',
        'ch_done', 2500, 0, null
    )::jsonb,
    '{"outcome":"noop"}'::jsonb,
    'Should noop for already completed purchases'
);

-- Should queue a late direct payment while a newer offer remains active
select is(
    reconcile_event_purchase_for_checkout_session(
        'stripe',
        'acct_complete',
        'cs_expired_active_offer',
        'pi_expired_active_offer',
        'ch_expired_active_offer',
        2500,
        0,
        null
    )::jsonb,
    jsonb_build_object('outcome', 'refund_queued'),
    'Should queue a late direct payment while a newer offer remains active'
);

select results_eq(
    format(
        $$
            select
                ao.status,
                ep.status,
                epr.status
            from admission_offer ao
            join event_purchase ep
                on ep.event_id = ao.event_id
                and ep.user_id = ao.user_id
            join event_purchase_refund epr using (event_purchase_id)
            where ao.admission_offer_id = %L::uuid
            and ep.event_purchase_id = %L::uuid
        $$,
        :'activeOfferRefundOfferID',
        :'activeOfferRefundPurchaseID'
    ),
    $$ values ('pending'::text, 'refund-pending'::text, 'provider-pending'::text) $$,
    'Should preserve the active offer and durable refund handoff'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
