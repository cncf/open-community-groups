-- Tests listing active event admission offers owned by a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID '4a0b0000-0000-0000-0000-000000000001'
\set acceptedOfferID '4a0b0000-0000-0000-0000-00000000001a'
\set bouncedDiscountCodeID '4a0b0000-0000-0000-0000-000000000029'
\set bouncedDiscountOfferID '4a0b0000-0000-0000-0000-000000000027'
\set bouncedDiscountUserID '4a0b0000-0000-0000-0000-000000000028'
\set canceledEventID '4a0b0000-0000-0000-0000-000000000002'
\set canceledOfferID '4a0b0000-0000-0000-0000-000000000018'
\set communityID '4a0b0000-0000-0000-0000-000000000003'
\set endedWindowApprovalOfferID '4a0b0000-0000-0000-0000-00000000002a'
\set endedWindowApprovalUserID '4a0b0000-0000-0000-0000-00000000002b'
\set endedWindowEventID '4a0b0000-0000-0000-0000-00000000002c'
\set endedWindowPriceWindowID '4a0b0000-0000-0000-0000-00000000002d'
\set endedWindowTicketTypeID '4a0b0000-0000-0000-0000-00000000002e'
\set endedWindowWaitlistOfferID '4a0b0000-0000-0000-0000-00000000002f'
\set endedWindowWaitlistUserID '4a0b0000-0000-0000-0000-000000000030'
\set eventCategoryID '4a0b0000-0000-0000-0000-000000000004'
\set eventID '4a0b0000-0000-0000-0000-000000000005'
\set eventTicketedID '4a0b0000-0000-0000-0000-000000000012'
\set externalOfferID '4a0b0000-0000-0000-0000-000000000031'
\set externalPurchaseID '4a0b0000-0000-0000-0000-000000000032'
\set externalUserID '4a0b0000-0000-0000-0000-000000000033'
\set groupCategoryID '4a0b0000-0000-0000-0000-000000000006'
\set groupID '4a0b0000-0000-0000-0000-000000000007'
\set inactiveGroupEventID '4a0b0000-0000-0000-0000-000000000008'
\set inactiveGroupID '4a0b0000-0000-0000-0000-000000000009'
\set inactiveGroupOfferID '4a0b0000-0000-0000-0000-000000000019'
\set invitedUserID '4a0b0000-0000-0000-0000-000000000010'
\set invitedOfferID '4a0b0000-0000-0000-0000-000000000013'
\set livePriceOfferID '4a0b0000-0000-0000-0000-000000000025'
\set livePriceUserID '4a0b0000-0000-0000-0000-000000000026'
\set privateOfferID '4a0b0000-0000-0000-0000-00000000001e'
\set privatePriceWindowID '4a0b0000-0000-0000-0000-00000000001f'
\set privateTicketTypeID '4a0b0000-0000-0000-0000-000000000020'
\set privateUserID '4a0b0000-0000-0000-0000-000000000021'
\set priceWindowID '4a0b0000-0000-0000-0000-000000000014'
\set questionID '4a0b0000-0000-0000-0000-00000000001c'
\set refundOfferID '4a0b0000-0000-0000-0000-000000000022'
\set refundPurchaseID '4a0b0000-0000-0000-0000-000000000023'
\set refundUserID '4a0b0000-0000-0000-0000-000000000024'
\set rejectedOfferID '4a0b0000-0000-0000-0000-00000000001b'
\set rejectedUserID '4a0b0000-0000-0000-0000-000000000011'
\set ticketOfferID '4a0b0000-0000-0000-0000-000000000015'
\set ticketPurchaseID '4a0b0000-0000-0000-0000-00000000001d'
\set ticketTypeID '4a0b0000-0000-0000-0000-000000000016'
\set ticketUserID '4a0b0000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
select fx_community(:'communityID', jsonb_build_object(
    'display_name', 'Event Invitations Community',
    'name', 'event-invitations-community'
));

-- Baseline group categories, event categories and users
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'bouncedDiscountUserID');
select fx_user(:'endedWindowApprovalUserID');
select fx_user(:'endedWindowWaitlistUserID');
select fx_user(:'externalUserID');
select fx_user(:'invitedUserID');
select fx_user(:'livePriceUserID');
select fx_user(:'privateUserID');
select fx_user(:'refundUserID');
select fx_user(:'rejectedUserID');
select fx_user(:'ticketUserID');

-- Users
select fx_user(:'acceptedUserID', jsonb_build_object('username', 'accepted'));

-- Groups
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Event Invitations Group'));
select fx_group(:'inactiveGroupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Future Event',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2099-01-02 10:00:00+00'
));
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2099-01-03 10:00:00+00'
));

-- Ticketed event hosting the approval offer and external checkout
select fx_event(:'eventTicketedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_instructions', 'Transfer to the club IBAN and include the reference',
    'external_payment_url', 'https://pay.example.test/invitations-external',
    'name', 'Ticket Event',
    'payment_currency_code', 'USD',
    'published', true,
    'registration_questions', format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Meal", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'starts_at', '2099-01-05 10:00:00+00'
));

select fx_event(:'inactiveGroupEventID', :'inactiveGroupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2099-01-04 10:00:00+00'
));

-- Event whose ticket sales window has ended
select fx_event(:'endedWindowEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'EUR',
    'published', true,
    'starts_at', '2099-01-06 10:00:00+00'
));

-- Ticket tier assigned by the approval offer
select fx_event_ticket_type(:'ticketTypeID', :'eventTicketedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Paid price window for the ticket tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- Discount used by the bounced-back pending snapshot fixture
insert into event_discount_code (
    event_discount_code_id,
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_id,
    kind,
    title
) values (
    :'bouncedDiscountCodeID',
    true,
    500,
    1,
    true,
    'SAVE10',
    :'eventTicketedID',
    'fixed_amount',
    'Bounced save'
);

-- Ticket tier whose sales window has already ended
select fx_event_ticket_type(:'endedWindowTicketTypeID', :'endedWindowEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Ended window admission'
));

-- Lapsed price window used by ended-window offer display scenarios
select fx_event_ticket_price_window(:'endedWindowPriceWindowID', :'endedWindowTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', current_timestamp - interval '1 minute',
    'starts_at', current_timestamp - interval '2 days'
));

-- Events without an explicit ticket fixture use default admission tiers
select fx_event_ticket_type(
    md5(e.event_id::text || ':ticket-type')::uuid,
    e.event_id,
    jsonb_build_object(
        'seats_total', 100,
        'title', 'General Admission'
    )
)
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Current free prices for the default admission tiers
select fx_event_ticket_price_window(
    md5(ett.event_ticket_type_id::text || ':price-window')::uuid,
    ett.event_ticket_type_id,
    jsonb_build_object('amount_minor', 0)
)
from event_ticket_type ett
where not exists (
    select 1
    from event_ticket_price_window etpw
    where etpw.event_ticket_type_id = ett.event_ticket_type_id
);

-- Paid private tier alongside the event's free public RSVP tier
select fx_event_ticket_type(:'privateTicketTypeID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 10,
    'title', 'Private supporter'
));

select fx_event_ticket_price_window(:'privatePriceWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Event invitation offer states
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
)
values
    (
        :'acceptedOfferID',
        0,
        '2024-01-05 10:00:00+00',
        null,
        0,
        null,
        :'eventID',
        (
            select event_ticket_type_id
            from event_ticket_type
            where event_id = :'eventID'
            and availability = 'public'
            limit 1
        ),
        '2099-01-05 10:00:00+00',
        'organizer_invitation',
        'completed',
        'General Admission',
        :'acceptedUserID'
    ),
    (
        :'canceledOfferID',
        0,
        '2024-01-03 10:00:00+00',
        null,
        0,
        null,
        :'canceledEventID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'canceledEventID' limit 1),
        '2099-01-03 10:00:00+00',
        'organizer_invitation',
        'pending',
        'General Admission',
        :'invitedUserID'
    ),
    (
        :'inactiveGroupOfferID',
        0,
        '2024-01-04 10:00:00+00',
        null,
        0,
        null,
        :'inactiveGroupEventID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'inactiveGroupEventID' limit 1),
        '2099-01-04 10:00:00+00',
        'organizer_invitation',
        'pending',
        'General Admission',
        :'invitedUserID'
    ),
    (
        :'invitedOfferID',
        0,
        '2024-01-02 10:00:00+00',
        null,
        0,
        null,
        :'eventID',
        (
            select event_ticket_type_id
            from event_ticket_type
            where event_id = :'eventID'
            and availability = 'public'
            limit 1
        ),
        '2099-01-02 10:00:00+00',
        'organizer_invitation',
        'pending',
        'General Admission',
        :'invitedUserID'
    ),
    (
        :'livePriceOfferID',
        0,
        '2024-01-10 10:00:00+00',
        null,
        0,
        null,
        :'eventTicketedID',
        :'ticketTypeID',
        '2099-01-05 10:00:00+00',
        'approval',
        'pending',
        'General admission',
        :'livePriceUserID'
    ),
    (
        :'privateOfferID',
        2500,
        '2024-01-08 10:00:00+00',
        'USD',
        0,
        null,
        :'eventID',
        :'privateTicketTypeID',
        '2099-01-02 10:00:00+00',
        'organizer_invitation',
        'pending',
        'Private supporter',
        :'privateUserID'
    ),
    (
        :'refundOfferID',
        1000,
        '2024-01-09 10:00:00+00',
        'USD',
        0,
        null,
        :'eventTicketedID',
        :'ticketTypeID',
        '2099-01-05 10:00:00+00',
        'approval',
        'checkout_pending',
        'General admission',
        :'refundUserID'
    ),
    (
        :'rejectedOfferID',
        0,
        '2024-01-06 10:00:00+00',
        null,
        0,
        null,
        :'eventID',
        (
            select event_ticket_type_id
            from event_ticket_type
            where event_id = :'eventID'
            and availability = 'public'
            limit 1
        ),
        '2099-01-06 10:00:00+00',
        'organizer_invitation',
        'declined',
        'General Admission',
        :'rejectedUserID'
    ),
    (
        :'ticketOfferID',
        1000,
        '2024-01-07 10:00:00+00',
        'USD',
        0,
        null,
        :'eventTicketedID',
        :'ticketTypeID',
        '2099-01-05 10:00:00+00',
        'approval',
        'checkout_pending',
        'General admission',
        :'ticketUserID'
    );

-- Checkout-pending offer paid through an external purchase hold
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
    :'externalOfferID',
    1000,
    '2024-01-13 10:00:00+00',
    'USD',
    0,
    :'eventTicketedID',
    :'ticketTypeID',
    '2099-01-05 10:00:00+00',
    'approval',
    'checkout_pending',
    'General admission',
    :'externalUserID'
);

-- Pending discounted offer frozen after an abandoned checkout
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values (
    :'bouncedDiscountOfferID',
    500,
    '2024-01-11 10:00:00+00',
    'USD',
    500,
    'SAVE10',
    :'bouncedDiscountCodeID',
    :'eventTicketedID',
    :'ticketTypeID',
    '2099-01-05 10:00:00+00',
    'approval',
    'pending',
    'General admission',
    :'bouncedDiscountUserID'
);

-- Pending offers that keep or omit a stored snapshot after sales end
insert into admission_offer (
    admission_offer_id,
    amount_minor,
    created_at,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    ticket_title,
    user_id
) values
    (
        :'endedWindowApprovalOfferID',
        2500,
        '2024-01-12 10:00:00+00',
        'USD',
        0,
        null,
        :'endedWindowEventID',
        :'endedWindowTicketTypeID',
        '2099-01-06 10:00:00+00',
        'approval',
        'pending',
        'Ended window admission',
        :'endedWindowApprovalUserID'
    ),
    (
        :'endedWindowWaitlistOfferID',
        2500,
        '2024-01-12 10:00:00+00',
        'USD',
        0,
        null,
        :'endedWindowEventID',
        :'endedWindowTicketTypeID',
        '2099-01-06 10:00:00+00',
        'waitlist',
        'pending',
        'Ended window admission',
        :'endedWindowWaitlistUserID'
    );

-- Accepted ticket request that supplies claim-time registration answers
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id,
    status,
    registration_answers,
    reviewed_at,
    reviewed_by
) values (
    :'eventTicketedID',
    :'ticketTypeID',
    :'ticketUserID',
    'accepted',
    format(
        '{"answers": [{"question_id": "%s", "value": "Vegetarian"}]}',
        :'questionID'
    )::jsonb,
    '2024-01-07 11:00:00+00',
    :'acceptedUserID'
);

-- Stale checkout attendee answers superseded by the accepted approval request
insert into event_attendee (
    event_id,
    registration_answers,
    status,
    user_id
) values (
    :'eventTicketedID',
    format(
        '{"answers": [{"question_id": "%s", "value": "Stale answer"}]}',
        :'questionID'
    )::jsonb,
    'registration-questions-pending',
    :'ticketUserID'
);

-- Pending checkout linked to the ticket offer
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
    provider_object_account_id,
    provider_checkout_url,
    seller_snapshot,
    status,
    tax_behavior,
    tax_calculation_mode,
    tax_classification,
    ticket_title,
    user_id,
    venue_snapshot,

    admission_offer_id
) values (
    :'ticketPurchaseID',
    1000,
    'direct-charge',
    'acct_user_invitations_test',
    'USD',
    :'eventTicketedID',
    :'ticketTypeID',
    '2099-01-05 09:00:00+00',
    'stripe',
    'acct_user_invitations_test',
    'https://example.test/checkout/resume',
    '{}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'ticketUserID',
    '{}'::jsonb,

    :'ticketOfferID'
);

-- Pending external purchase linked to the external checkout offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    platform_fee_bps,
    provider_checkout_url,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    :'externalOfferID',
    1000,
    'external',
    'USD',
    :'eventTicketedID',
    :'externalPurchaseID',
    :'ticketTypeID',
    '2099-01-05 12:00:00+00',
    0,
    'https://example.test/checkout/should-not-resume',
    0,
    'pending',
    'General admission',
    :'externalUserID'
);

-- Refund-processing purchase that suppresses its linked offer
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
    final_platform_fee_amount_minor,
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
    venue_snapshot
) values (
    :'refundOfferID',
    1000,
    'direct-charge',
    'acct_user_invitations_test',
    'USD',
    0,
    :'eventTicketedID',
    :'refundPurchaseID',
    :'ticketTypeID',
    0,
    'stripe',
    'ch_user_invitations_refund',
    'cs_user_invitations_refund',
    'acct_user_invitations_test',
    'pi_user_invitations_refund',
    1000,
    '{}'::jsonb,
    'refund-pending',
    1000,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'refundUserID',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active pending event invitations for a user
select is(
    list_user_event_invitations(:'invitedUserID'::uuid)::jsonb,
    format(
        $json$
            [
                {
                    "admission_offer_id": "%s",
                    "admission_offer_source": "organizer_invitation",
                    "admission_offer_status": "pending",
                    "community_display_name": "Event Invitations Community",
                    "community_name": "event-invitations-community",
                    "created_at": 1704189600,
                    "event_id": "%s",
                    "event_name": "Future Event",
                    "group_name": "Event Invitations Group",
                    "timezone": "UTC",
                    "amount_minor": 0,
                    "event_ticket_type_id": "%s",
                    "expires_at": 4071031200,
                    "is_simple_rsvp": true,
                    "registration_questions": [],
                    "starts_at": 4071031200,
                    "ticket_title": "General Admission"
                }
            ]
        $json$,
        :'invitedOfferID',
        :'eventID',
        (
            select event_ticket_type_id
            from event_ticket_type
            where event_id = :'eventID'
            and availability = 'public'
            limit 1
        )
    )::jsonb,
    'Should list active pending event invitations for the user'
);

-- Should expose external payment details on a checkout-pending offer
select is(
    (
        select jsonb_build_object(
            'external_payment',
            invitation->'external_payment',
            'has_resume_checkout_url',
            invitation ? 'resume_checkout_url'
        )
        from (
            select list_user_event_invitations(:'externalUserID'::uuid)::jsonb->0 as invitation
        ) listed
    ),
    jsonb_build_object(
        'external_payment',
        jsonb_build_object(
            'amount_minor',
            1000,
            'currency_code',
            'USD',
            'deadline',
            4071297600,
            'reference',
            :'externalPurchaseID',
            'url',
            'https://pay.example.test/invitations-external',
            'instructions',
            'Transfer to the club IBAN and include the reference'
        ),
        'has_resume_checkout_url',
        false
    ),
    'Should expose external payment details on a checkout-pending offer'
);

-- Should expose the exact assigned tier on an owned ticket offer
select is(
    list_user_event_invitations(:'ticketUserID'::uuid)::jsonb,
    format(
        $json$
            [
                {
                    "admission_offer_id": "%s",
                    "admission_offer_source": "approval",
                    "admission_offer_status": "checkout_pending",
                    "community_display_name": "Event Invitations Community",
                    "community_name": "event-invitations-community",
                    "created_at": 1704621600,
                    "event_id": "%s",
                    "event_name": "Ticket Event",
                    "group_name": "Event Invitations Group",
                    "timezone": "UTC",
                    "amount_minor": 1000,
                    "currency_code": "USD",
                    "event_ticket_type_id": "%s",
                    "expires_at": 4071290400,
                    "is_simple_rsvp": false,
                    "registration_answers": {
                        "answers": [
                            {
                                "question_id": "%s",
                                "value": "Vegetarian"
                            }
                        ]
                    },
                    "registration_questions": [
                        {
                            "id": "%s",
                            "kind": "free-text",
                            "options": [],
                            "prompt": "Meal",
                            "required": true
                        }
                    ],
                    "resume_checkout_url": "https://example.test/checkout/resume",
                    "starts_at": 4071290400,
                    "ticket_title": "General admission"
                }
            ]
        $json$,
        :'ticketOfferID',
        :'eventTicketedID',
        :'ticketTypeID',
        :'questionID',
        :'questionID'
    )::jsonb,
    'Should expose the exact assigned tier on an owned ticket offer'
);

-- Pending discounted offers keep the stored snapshot instead of the live window
select is(
    (
        select jsonb_build_object(
            'amount_minor', (list_user_event_invitations(:'bouncedDiscountUserID'::uuid)::jsonb->0->>'amount_minor')::bigint,
            'currency_code', list_user_event_invitations(:'bouncedDiscountUserID'::uuid)::jsonb->0->>'currency_code'
        )
    ),
    '{"amount_minor": 500, "currency_code": "USD"}'::jsonb,
    'Should list the stored snapshot for a pending discounted offer'
);

-- Pending offers prefer the live price window over the issue-time snapshot
select is(
    (
        select jsonb_build_object(
            'amount_minor', (list_user_event_invitations(:'livePriceUserID'::uuid)::jsonb->0->>'amount_minor')::bigint,
            'currency_code', list_user_event_invitations(:'livePriceUserID'::uuid)::jsonb->0->>'currency_code'
        )
    ),
    '{"amount_minor": 1000, "currency_code": "USD"}'::jsonb,
    'Should list the live ticket price for a pending offer with a stale free snapshot'
);

-- Pending approval offers keep the stored snapshot currency after sales end
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', list_user_event_invitations(:'endedWindowApprovalUserID'::uuid)::jsonb->0->>'admission_offer_id',
            'amount_minor', (list_user_event_invitations(:'endedWindowApprovalUserID'::uuid)::jsonb->0->>'amount_minor')::bigint,
            'currency_code', list_user_event_invitations(:'endedWindowApprovalUserID'::uuid)::jsonb->0->>'currency_code'
        )
    ),
    jsonb_build_object(
        'admission_offer_id', :'endedWindowApprovalOfferID',
        'amount_minor', 2500,
        'currency_code', 'USD'
    ),
    'Should list the stored snapshot currency for a pending approval offer after sales end'
);

-- Pending waitlist offers omit the stored snapshot after sales end
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', list_user_event_invitations(:'endedWindowWaitlistUserID'::uuid)::jsonb->0->>'admission_offer_id',
            'amount_minor', (list_user_event_invitations(:'endedWindowWaitlistUserID'::uuid)::jsonb->0->>'amount_minor')::bigint,
            'currency_code', list_user_event_invitations(:'endedWindowWaitlistUserID'::uuid)::jsonb->0->>'currency_code'
        )
    ),
    jsonb_build_object(
        'admission_offer_id', :'endedWindowWaitlistOfferID',
        'amount_minor', null,
        'currency_code', null
    ),
    'Should omit the stored snapshot for a pending waitlist offer after sales end'
);

-- Offers on a private paid tier use ticket wording even for a simple RSVP event
select is(
    (list_user_event_invitations(:'privateUserID'::uuid)::jsonb->0->>'is_simple_rsvp')::boolean,
    false,
    'Should use ticket wording for a private paid offer on a simple RSVP event'
);

-- Automatic refunds keep the ticket offer unavailable until they finish
select is(
    list_user_event_invitations(:'refundUserID'::uuid)::text,
    '[]',
    'Should hide ticket offers while their automatic refund is pending'
);

-- Should not list accepted event invitations
select is(
    list_user_event_invitations(:'acceptedUserID'::uuid)::text,
    '[]',
    'Should not list accepted event invitations'
);

-- Should not list rejected event invitations
select is(
    list_user_event_invitations(:'rejectedUserID'::uuid)::text,
    '[]',
    'Should not list rejected event invitations'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
