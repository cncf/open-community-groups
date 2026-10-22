-- Tests listing active event admission offers owned by a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedOfferID '4a0b0000-0000-0000-0000-00000000001a'
\set acceptedUserID '4a0b0000-0000-0000-0000-000000000001'
\set canceledEventID '4a0b0000-0000-0000-0000-000000000002'
\set canceledOfferID '4a0b0000-0000-0000-0000-000000000018'
\set canceledPriceWindowID '4a0b0000-0000-0000-0000-000000000034'
\set canceledTicketTypeID '4a0b0000-0000-0000-0000-000000000035'
\set communityID '4a0b0000-0000-0000-0000-000000000003'
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
\set inactiveGroupPriceWindowID '4a0b0000-0000-0000-0000-000000000036'
\set inactiveGroupTicketTypeID '4a0b0000-0000-0000-0000-000000000037'
\set invitedOfferID '4a0b0000-0000-0000-0000-000000000013'
\set invitedUserID '4a0b0000-0000-0000-0000-000000000010'
\set livePriceOfferID '4a0b0000-0000-0000-0000-000000000025'
\set livePriceUserID '4a0b0000-0000-0000-0000-000000000026'
\set priceWindowID '4a0b0000-0000-0000-0000-000000000014'
\set privateOfferID '4a0b0000-0000-0000-0000-00000000001e'
\set privatePriceWindowID '4a0b0000-0000-0000-0000-00000000001f'
\set privateTicketTypeID '4a0b0000-0000-0000-0000-000000000020'
\set privateUserID '4a0b0000-0000-0000-0000-000000000021'
\set publicPriceWindowID '4a0b0000-0000-0000-0000-000000000038'
\set publicTicketTypeID '4a0b0000-0000-0000-0000-000000000039'
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

-- Ticket tier assigned by the approval offer
select fx_event_ticket_type(:'ticketTypeID', :'eventTicketedID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Paid price window for the ticket tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 1000));

-- Default admission tiers for the RSVP events
select fx_event_ticket_type(:'canceledTicketTypeID', :'canceledEventID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'inactiveGroupTicketTypeID', :'inactiveGroupEventID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'publicTicketTypeID', :'eventID', jsonb_build_object('title', 'General Admission'));

-- Current free prices for the default admission tiers
select fx_event_ticket_price_window(:'canceledPriceWindowID', :'canceledTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'inactiveGroupPriceWindowID', :'inactiveGroupTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'publicPriceWindowID', :'publicTicketTypeID', jsonb_build_object('amount_minor', 0));

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
        :'publicTicketTypeID',
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
        :'canceledTicketTypeID',
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
        :'inactiveGroupTicketTypeID',
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
        :'publicTicketTypeID',
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
        :'publicTicketTypeID',
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

-- Should list active pending event invitations for the user
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
        :'publicTicketTypeID'
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

-- Should list the live ticket price for a pending offer with a stale free snapshot
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', listed.invitation->'admission_offer_id',
            'amount_minor', listed.invitation->'amount_minor',
            'currency_code', listed.invitation->'currency_code'
        )
        from (
            select list_user_event_invitations(:'livePriceUserID'::uuid)::jsonb->0 as invitation
        ) listed
    ),
    jsonb_build_object(
        'admission_offer_id', :'livePriceOfferID',
        'amount_minor', 1000,
        'currency_code', 'USD'
    ),
    'Should list the live ticket price for a pending offer with a stale free snapshot'
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
