-- Tests listing upcoming user event participation, active checkouts, and active offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(17);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeOrganizerUserID '4a0c0000-0000-0000-0000-000000000053'
\set checkoutExpiredPurchaseID '4a0c0000-0000-0000-0000-000000000040'
\set checkoutExpiredUserID '4a0c0000-0000-0000-0000-000000000041'
\set checkoutPurchaseID '4a0c0000-0000-0000-0000-000000000042'
\set checkoutUserID '4a0c0000-0000-0000-0000-000000000043'
\set communityID '4a0c0000-0000-0000-0000-000000000001'
\set eventAID '4a0c0000-0000-0000-0000-000000000002'
\set eventAPriceWindowID '4a0c0000-0000-0000-0000-000000000058'
\set eventATicketTypeID '4a0c0000-0000-0000-0000-000000000059'
\set eventBID '4a0c0000-0000-0000-0000-000000000003'
\set eventBPriceWindowID '4a0c0000-0000-0000-0000-00000000005a'
\set eventBTicketTypeID '4a0c0000-0000-0000-0000-00000000005b'
\set eventCanceledID '4a0c0000-0000-0000-0000-000000000004'
\set eventCanceledPriceWindowID '4a0c0000-0000-0000-0000-00000000005e'
\set eventCanceledTicketTypeID '4a0c0000-0000-0000-0000-00000000005f'
\set eventCategoryID '4a0c0000-0000-0000-0000-000000000005'
\set eventCID '4a0c0000-0000-0000-0000-000000000006'
\set eventCPriceWindowID '4a0c0000-0000-0000-0000-00000000005c'
\set eventCTicketTypeID '4a0c0000-0000-0000-0000-00000000005d'
\set eventInactiveGroupID '4a0c0000-0000-0000-0000-000000000009'
\set eventInactiveGroupPriceWindowID '4a0c0000-0000-0000-0000-000000000060'
\set eventInactiveGroupTicketTypeID '4a0c0000-0000-0000-0000-000000000061'
\set eventNoStartsAtID '4a0c0000-0000-0000-0000-000000000010'
\set eventNoStartsAtPriceWindowID '4a0c0000-0000-0000-0000-000000000062'
\set eventNoStartsAtTicketTypeID '4a0c0000-0000-0000-0000-000000000063'
\set eventPaidID '4a0c0000-0000-0000-0000-000000000011'
\set eventPaidPriceWindowID '4a0c0000-0000-0000-0000-000000000012'
\set eventPaidPurchaseID '4a0c0000-0000-0000-0000-000000000013'
\set eventPaidRefundRequestID '4a0c0000-0000-0000-0000-000000000044'
\set eventPaidTicketTypeID '4a0c0000-0000-0000-0000-000000000014'
\set eventPastID '4a0c0000-0000-0000-0000-000000000015'
\set eventPastPriceWindowID '4a0c0000-0000-0000-0000-000000000064'
\set eventPastTicketTypeID '4a0c0000-0000-0000-0000-000000000065'
\set eventPendingInvitationID '4a0c0000-0000-0000-0000-000000000016'
\set eventPendingInvitationPriceWindowID '4a0c0000-0000-0000-0000-000000000066'
\set eventPendingInvitationTicketTypeID '4a0c0000-0000-0000-0000-000000000067'
\set eventQuestionsID '4a0c0000-0000-0000-0000-000000000017'
\set eventQuestionsPriceWindowID '4a0c0000-0000-0000-0000-00000000006a'
\set eventQuestionsTicketTypeID '4a0c0000-0000-0000-0000-000000000018'
\set eventUnpublishedID '4a0c0000-0000-0000-0000-000000000019'
\set eventUnpublishedPriceWindowID '4a0c0000-0000-0000-0000-000000000068'
\set eventUnpublishedTicketTypeID '4a0c0000-0000-0000-0000-000000000069'
\set externalCheckoutPurchaseID '4a0c0000-0000-0000-0000-000000000051'
\set externalCheckoutUserID '4a0c0000-0000-0000-0000-000000000052'
\set groupCategoryID '4a0c0000-0000-0000-0000-000000000020'
\set groupID '4a0c0000-0000-0000-0000-000000000022'
\set groupInactiveID '4a0c0000-0000-0000-0000-000000000023'
\set livePriceOfferID '4a0c0000-0000-0000-0000-000000000047'
\set livePriceUserID '4a0c0000-0000-0000-0000-000000000048'
\set organizerOnlyUserID '4a0c0000-0000-0000-0000-000000000055'
\set pendingInvitationOfferID '4a0c0000-0000-0000-0000-000000000036'
\set questionsAttendeeUserID '4a0c0000-0000-0000-0000-000000000024'
\set questionsCheckoutExpiredPurchaseID '4a0c0000-0000-0000-0000-000000000025'
\set questionsCheckoutExpiredUserID '4a0c0000-0000-0000-0000-000000000026'
\set questionsCheckoutPurchaseID '4a0c0000-0000-0000-0000-000000000027'
\set questionsCheckoutUserID '4a0c0000-0000-0000-0000-000000000028'
\set questionsInvitationOfferID '4a0c0000-0000-0000-0000-000000000037'
\set questionsInvitedUserID '4a0c0000-0000-0000-0000-000000000029'
\set questionsRefundPendingOfferID '4a0c0000-0000-0000-0000-000000000038'
\set questionsRefundPendingUserID '4a0c0000-0000-0000-0000-000000000039'
\set registrationQuestionID '4a0c0000-0000-0000-0000-000000000030'
\set sessionAID '4a0c0000-0000-0000-0000-000000000031'
\set sessionCID '4a0c0000-0000-0000-0000-000000000032'
\set teamMemberUserID '4a0c0000-0000-0000-0000-000000000057'
\set userEmptyID '4a0c0000-0000-0000-0000-000000000033'
\set userID '4a0c0000-0000-0000-0000-000000000034'
\set userPaidID '4a0c0000-0000-0000-0000-000000000035'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'checkoutExpiredUserID');
select fx_user(:'checkoutUserID');
select fx_user(:'externalCheckoutUserID');
select fx_user(:'userID');
select fx_user(:'livePriceUserID');
select fx_user(:'userPaidID');
select fx_user(:'questionsAttendeeUserID');
select fx_user(:'questionsCheckoutUserID');
select fx_user(:'questionsCheckoutExpiredUserID');
select fx_user(:'questionsInvitedUserID');
select fx_user(:'questionsRefundPendingUserID');

-- User who attends and organizes the same event
select fx_user(:'attendeeOrganizerUserID');

-- User listed only as an event organizer
select fx_user(:'organizerOnlyUserID');

-- Accepted team member who is not stored as an event organizer
select fx_user(:'teamMemberUserID');

-- Group owning the listed events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Inactive group whose events stay hidden
select fx_group(:'groupInactiveID', :'communityID', :'groupCategoryID', jsonb_build_object('active', false));

-- Events
select fx_event(:'eventAID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', '2099-01-10 10:00:00+00'
));
select fx_event(:'eventBID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2099-01-11 10:00:00+00'
));
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'event_kind_id', 'virtual',
    'starts_at', '2099-01-13 10:00:00+00'
));
select fx_event(:'eventCID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2099-01-12 10:00:00+00'
));
select fx_event(:'eventInactiveGroupID', :'groupInactiveID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2099-01-15 10:00:00+00'
));
select fx_event(:'eventNoStartsAtID', :'groupID', :'eventCategoryID', jsonb_build_object('event_kind_id', 'virtual'));
select fx_event(:'eventPastID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2000-01-01 10:00:00+00'
));
select fx_event(:'eventPendingInvitationID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true,
    'starts_at', '2099-01-13 12:00:00+00'
));
select fx_event(:'eventUnpublishedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'starts_at', '2099-01-16 10:00:00+00'
));

-- Paid event that also hosts a pending external checkout
select fx_event(:'eventPaidID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'external_payment_instructions', 'Wire the fee to the organizer bank account',
    'external_payment_url', 'https://pay.example.test/external-checkout',
    'payment_currency_code', 'USD',
    'published', true,
    'starts_at', '2099-01-18 10:00:00+00'
));

-- Event with registration questions shown in user event lists
select fx_event(:'eventQuestionsID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'registration_questions', format(
        $json$
            [
                {
                    "id": "%s",
                    "kind": "free-text",
                    "prompt": "Note",
                    "required": true,
                    "options": []
                }
            ]
        $json$,
        :'registrationQuestionID'
    )::jsonb,
    'starts_at', now() + interval '1 day'
));

-- Accepted team member joining after the group events were created
insert into group_team (accepted, group_id, role, user_id)
values (true, :'groupID', 'viewer', :'teamMemberUserID');

-- Sessions for speaker role tests
insert into session (session_id, event_id, name, session_kind_id, starts_at) values
    (:'sessionAID', :'eventAID', 'Session A', 'virtual', '2099-01-10 11:00:00+00'),
    (:'sessionCID', :'eventCID', 'Session C', 'virtual', '2099-01-12 11:00:00+00');

-- Event ticket types
select fx_event_ticket_type(:'eventPaidTicketTypeID', :'eventPaidID', jsonb_build_object(
    'seats_total', 3,
    'title', 'Paid admission'
));
select fx_event_ticket_type(:'eventQuestionsTicketTypeID', :'eventQuestionsID', jsonb_build_object(
    'seats_total', 100,
    'title', 'Questions admission'
));

-- Paid ticket price window used by purchase state tests
select fx_event_ticket_price_window(:'eventPaidPriceWindowID', :'eventPaidTicketTypeID', jsonb_build_object('amount_minor', 1500));

-- Current free price for the registration-questions tier
select fx_event_ticket_price_window(:'eventQuestionsPriceWindowID', :'eventQuestionsTicketTypeID', jsonb_build_object('amount_minor', 0));

-- Default admission tiers for the RSVP events
select fx_event_ticket_type(:'eventATicketTypeID', :'eventAID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventBTicketTypeID', :'eventBID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventCTicketTypeID', :'eventCID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventCanceledTicketTypeID', :'eventCanceledID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventInactiveGroupTicketTypeID', :'eventInactiveGroupID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventNoStartsAtTicketTypeID', :'eventNoStartsAtID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventPastTicketTypeID', :'eventPastID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventPendingInvitationTicketTypeID', :'eventPendingInvitationID', jsonb_build_object('title', 'General Admission'));
select fx_event_ticket_type(:'eventUnpublishedTicketTypeID', :'eventUnpublishedID', jsonb_build_object('title', 'General Admission'));

-- Current free prices for the default admission tiers
select fx_event_ticket_price_window(:'eventAPriceWindowID', :'eventATicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventBPriceWindowID', :'eventBTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventCPriceWindowID', :'eventCTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventCanceledPriceWindowID', :'eventCanceledTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventInactiveGroupPriceWindowID', :'eventInactiveGroupTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventNoStartsAtPriceWindowID', :'eventNoStartsAtTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventPastPriceWindowID', :'eventPastTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventPendingInvitationPriceWindowID', :'eventPendingInvitationTicketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'eventUnpublishedPriceWindowID', :'eventUnpublishedTicketTypeID', jsonb_build_object('amount_minor', 0));

-- User participation
insert into event_attendee (event_id, user_id, status) values
    (:'eventAID', :'userID', 'confirmed'),
    (:'eventBID', :'userID', 'confirmed'),
    (:'eventCanceledID', :'userID', 'confirmed'),
    (:'eventInactiveGroupID', :'userID', 'confirmed'),
    (:'eventNoStartsAtID', :'userID', 'confirmed'),
    (:'eventPastID', :'userID', 'confirmed'),
    (:'eventPaidID', :'userPaidID', 'confirmed'),
    (:'eventUnpublishedID', :'userID', 'confirmed');

-- Attendance of the user who also organizes the event
insert into event_attendee (event_id, user_id, status)
values (:'eventBID', :'attendeeOrganizerUserID', 'confirmed');

-- Organizer invitation offers included in the user's event list
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'pendingInvitationOfferID',
    :'eventPendingInvitationID',
    :'eventPendingInvitationTicketTypeID',
    '2099-01-13 11:00:00+00',
    'organizer_invitation',
    'pending',
    :'userID'
), (
    :'questionsInvitationOfferID',
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    '2099-01-13 11:00:00+00',
    'organizer_invitation',
    'pending',
    :'questionsInvitedUserID'
);

-- Pending approval offer with a stale free snapshot on the paid tier
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
    :'livePriceOfferID',
    0,
    null,
    0,
    :'eventPaidID',
    :'eventPaidTicketTypeID',
    '2099-01-18 11:00:00+00',
    'approval',
    'pending',
    'Paid admission',
    :'livePriceUserID'
);

-- Organizer invitation offer hidden while its refund is processing
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'questionsRefundPendingOfferID',
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    '2099-01-13 11:00:00+00',
    'organizer_invitation',
    'pending',
    :'questionsRefundPendingUserID'
);

-- User event rows for registration-question states
insert into event_attendee (event_id, user_id, manually_invited, status, registration_answers)
values
    (
        :'eventQuestionsID',
        :'questionsCheckoutUserID',
        false,
        'registration-questions-pending',
        format(
            '{"answers": [{"question_id": "%s", "value": "Checkout answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsCheckoutExpiredUserID',
        false,
        'registration-questions-pending',
        format(
            '{"answers": [{"question_id": "%s", "value": "Expired answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    ),
    (
        :'eventQuestionsID',
        :'questionsAttendeeUserID',
        false,
        'confirmed',
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'registrationQuestionID'
        )::jsonb
    );

-- User roles for role aggregation
insert into event_host (event_id, user_id) values
    (:'eventAID', :'userID');

-- Organizer relationship of the user who also attends the event
insert into event_organizer (event_id, user_id, "order")
values (:'eventBID', :'attendeeOrganizerUserID', 1);

-- Organizer-only relationship included in the user's event list
insert into event_organizer (event_id, user_id, "order")
values (:'eventCID', :'organizerOnlyUserID', 1);

-- Event speaker relationship included in the user's event list
insert into event_speaker (event_id, user_id, featured) values
    (:'eventAID', :'userID', true);

-- Session speaker relationships included in the user's event list
insert into session_speaker (session_id, user_id, featured) values
    (:'sessionAID', :'userID', false),
    (:'sessionCID', :'userID', true);

-- Completed paid purchase used to disable attendee cancellation
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
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
    :'eventPaidPurchaseID',
    1500,
    'direct-charge',
    'acct_user_events_test',
    'USD',
    :'eventPaidID',
    :'eventPaidTicketTypeID',
    0,
    'stripe',
    'ch_user_events_paid',
    'cs_user_events_paid',
    'acct_user_events_test',
    'pi_user_events_paid',
    1500,
    '{}'::jsonb,
    'completed',
    1500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'Paid admission',
    :'userPaidID',
    '{}'::jsonb
);

-- Rejected refund request shown with the paid event in My Events
insert into event_refund_request (
    event_purchase_id,
    event_refund_request_id,
    requested_by_user_id,
    status,

    requested_reason,
    review_note,
    reviewed_at,
    reviewed_by_user_id
) values (
    :'eventPaidPurchaseID',
    :'eventPaidRefundRequestID',
    :'userPaidID',
    'rejected',

    'Plans changed',
    'Outside the refund policy window',
    '2026-01-04 11:00:00+00',
    :'userID'
);

-- Pending checkout purchases used to distinguish active and expired holds
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
    venue_snapshot
)
select
    fixture.event_purchase_id,
    1500,
    'direct-charge',
    'acct_user_events_test',
    'USD',
    fixture.event_id,
    fixture.event_ticket_type_id,
    fixture.hold_expires_at,
    'stripe',
    'acct_user_events_test',
    fixture.provider_checkout_url,
    '{}'::jsonb,
    'pending',
    'inclusive',
    'manual',
    'professional-event-admission',
    fixture.ticket_title,
    fixture.user_id,
    '{}'::jsonb
from (values
    (
        :'checkoutPurchaseID'::uuid,
        :'eventPaidID'::uuid,
        :'eventPaidTicketTypeID'::uuid,
        current_timestamp + interval '10 minutes',
        'https://example.test/checkout/direct-resume',
        'Paid admission',
        :'checkoutUserID'::uuid
    ),
    (
        :'checkoutExpiredPurchaseID'::uuid,
        :'eventPaidID'::uuid,
        :'eventPaidTicketTypeID'::uuid,
        current_timestamp - interval '10 minutes',
        'https://example.test/checkout/direct-expired',
        'Paid admission',
        :'checkoutExpiredUserID'::uuid
    ),
    (
        :'questionsCheckoutPurchaseID'::uuid,
        :'eventQuestionsID'::uuid,
        :'eventQuestionsTicketTypeID'::uuid,
        current_timestamp + interval '10 minutes',
        'https://example.test/checkout/resume',
        'Questions admission',
        :'questionsCheckoutUserID'::uuid
    ),
    (
        :'questionsCheckoutExpiredPurchaseID'::uuid,
        :'eventQuestionsID'::uuid,
        :'eventQuestionsTicketTypeID'::uuid,
        current_timestamp - interval '10 minutes',
        'https://example.test/checkout/expired',
        'Questions admission',
        :'questionsCheckoutExpiredUserID'::uuid
    )
) as fixture(
    event_purchase_id,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    provider_checkout_url,
    ticket_title,
    user_id
);

-- Pending external checkout that exposes payment details instead of a resume URL
insert into event_purchase (
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
    1500,
    'external',
    'USD',
    :'eventPaidID',
    :'externalCheckoutPurchaseID',
    :'eventPaidTicketTypeID',
    '2099-01-18 09:00:00+00',
    0,
    'https://example.test/checkout/should-not-resume',
    0,
    'pending',
    'Paid admission',
    :'externalCheckoutUserID'
);

-- Refund-pending purchase that suppresses its linked invitation offer
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    charge_model,
    connected_seller_id,
    currency_code,
    event_id,
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
    :'questionsRefundPendingOfferID',
    1500,
    'direct-charge',
    'acct_user_events_test',
    'USD',
    :'eventQuestionsID',
    :'eventQuestionsTicketTypeID',
    0,
    'stripe',
    'ch_user_events_refund',
    'cs_user_events_refund',
    'acct_user_events_test',
    'pi_user_events_refund',
    1500,
    '{}'::jsonb,
    'refund-pending',
    1500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'Questions admission',
    :'questionsRefundPendingUserID',
    '{}'::jsonb
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list only valid upcoming events sorted by date asc
select is(
    list_user_events(:'userID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventAID'::uuid)::jsonb,
                'enrollment_status',
                'attendee',
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventAID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('attendee', 'host', 'speaker')
            ),
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'enrollment_status',
                'attendee',
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventBID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('attendee')
            ),
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventCID'::uuid)::jsonb,
                'enrollment_status',
                null,
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventCID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('speaker')
            ),
            jsonb_build_object(
                'admission_offer_id',
                :'pendingInvitationOfferID',
                'admission_offer_source',
                'organizer_invitation',
                'admission_offer_status',
                'pending',
                'amount_minor',
                0,
                'event',
                get_event_summary(
                    :'communityID'::uuid,
                    :'groupID'::uuid,
                    :'eventPendingInvitationID'::uuid
                )::jsonb,
                'enrollment_status',
                'invitation-approved',
                'event_ticket_type_id',
                :'eventPendingInvitationTicketTypeID',
                'has_paid_purchase',
                false,
                'manually_invited',
                true,
                'offer_expires_at',
                4071985200,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(
                    :'communityID'::uuid,
                    :'eventPendingInvitationID'::uuid
                )::jsonb,
                'roles',
                jsonb_build_array('offer'),
                'ticket_title',
                'General Admission'
            )
        ),
        'total',
        4
    ),
    'Should list valid upcoming participation and offers sorted by date asc'
);

-- Should paginate events and keep total count
select is(
    list_user_events(:'userID'::uuid, '{"limit": 1, "offset": 1}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventBID'::uuid)::jsonb,
                'enrollment_status',
                'attendee',
                'has_paid_purchase',
                false,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventBID'::uuid)::jsonb,
                'roles',
                jsonb_build_array('attendee')
            )
        ),
        'total',
        4
    ),
    'Should paginate events and keep total count'
);

-- Should not allow paid attendee-only events to be canceled from My Events
select is(
    list_user_events(:'userPaidID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        jsonb_build_array(
            jsonb_build_object(
                'event',
                get_event_summary(:'communityID'::uuid, :'groupID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'enrollment_status',
                'attendee',
                'has_paid_purchase',
                true,
                'registration_answers',
                null,
                'registration_questions',
                get_event_registration_questions(:'communityID'::uuid, :'eventPaidID'::uuid)::jsonb,
                'refund_rejection_reason',
                'Outside the refund policy window',
                'refund_request_status',
                'rejected',
                'roles',
                jsonb_build_array('attendee')
            )
        ),
        'total',
        1
    ),
    'Should not allow paid attendee-only events to be canceled from My Events'
);

-- Should return empty result for users without events
select is(
    list_user_events(:'userEmptyID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should return empty result for users without events'
);

-- Should list attendee and organizer roles for an attendee organizer
select is(
    list_user_events(:'attendeeOrganizerUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
        -> 'roles',
    jsonb_build_array('attendee', 'organizer'),
    'Should list attendee and organizer roles for an attendee organizer'
);

-- Should list an organizer-only event with the organizer role
select is(
    (
        select jsonb_build_object(
            'event_id', listed->'events'->0->'event'->>'event_id',
            'roles', listed->'events'->0->'roles',
            'total', listed->'total'
        )
        from (
            select list_user_events(:'organizerOnlyUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb as listed
        ) result
    ),
    jsonb_build_object(
        'event_id', :'eventCID',
        'roles', jsonb_build_array('organizer'),
        'total', 1
    ),
    'Should list an organizer-only event with the organizer role'
);

-- Should not list existing events for a team member who is not a stored organizer
select is(
    list_user_events(:'teamMemberUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should not list existing events for a team member who is not a stored organizer'
);

-- Should include active organizer ticket offers without labeling recipients as attendees
select is(
    (
        list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'admission_offer_id',
        :'questionsInvitationOfferID',
        'admission_offer_source',
        'organizer_invitation',
        'admission_offer_status',
        'pending',
        'amount_minor',
        0,
        'enrollment_status',
        'invitation-approved',
        'event_ticket_type_id',
        :'eventQuestionsTicketTypeID',
        'has_paid_purchase',
        false,
        'manually_invited',
        true,
        'offer_expires_at',
        4071985200,
        'registration_answers',
        null,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'roles',
        jsonb_build_array('offer'),
        'ticket_title',
        'Questions admission'
    ),
    'Should include active organizer ticket offers without labeling recipients as attendees'
);

-- Should list the live ticket price for a pending offer with a stale free snapshot
select is(
    (
        select jsonb_build_object(
            'admission_offer_id', listed.event->'admission_offer_id',
            'amount_minor', listed.event->'amount_minor',
            'currency_code', listed.event->'currency_code'
        )
        from (
            select list_user_events(
                :'livePriceUserID'::uuid,
                '{"limit": 10, "offset": 0}'::jsonb
            )::jsonb->'events'->0 as event
        ) listed
    ),
    jsonb_build_object(
        'admission_offer_id', :'livePriceOfferID',
        'amount_minor', 1500,
        'currency_code', 'USD'
    ),
    'Should list the live ticket price for a pending offer with a stale free snapshot'
);

-- Should include active direct checkout without labeling the user as an attendee
select is(
    (
        list_user_events(:'checkoutUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'amount_minor',
        1500,
        'currency_code',
        'USD',
        'enrollment_status',
        'pending-payment',
        'event_ticket_type_id',
        :'eventPaidTicketTypeID',
        'has_paid_purchase',
        false,
        'registration_answers',
        null,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventPaidID'::uuid)::jsonb,
        'resume_checkout_url',
        'https://example.test/checkout/direct-resume',
        'roles',
        '[]'::jsonb,
        'ticket_title',
        'Paid admission'
    ),
    'Should include active direct checkout without labeling the user as an attendee'
);

-- Should include active external checkout with payment details and without a resume URL
select is(
    (
        list_user_events(
            :'externalCheckoutUserID'::uuid,
            '{"limit": 10, "offset": 0}'::jsonb
        )::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'enrollment_status',
        'pending-payment',
        'has_paid_purchase',
        false,
        'registration_answers',
        null,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventPaidID'::uuid)::jsonb,
        'roles',
        '[]'::jsonb,
        'amount_minor',
        1500,
        'currency_code',
        'USD',
        'event_ticket_type_id',
        :'eventPaidTicketTypeID',
        'external_payment',
        jsonb_build_object(
            'amount_minor',
            1500,
            'currency_code',
            'USD',
            'deadline',
            4072410000,
            'reference',
            :'externalCheckoutPurchaseID',
            'url',
            'https://pay.example.test/external-checkout',
            'instructions',
            'Wire the fee to the organizer bank account'
        ),
        'ticket_title',
        'Paid admission'
    ),
    'Should include active external checkout with payment details and without a resume URL'
);

-- Should return registration questions for pending users
select is(
    list_user_events(:'questionsInvitedUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
        -> 'registration_questions',
    format(
        '[{"id": "%s", "kind": "free-text", "options": [], "prompt": "Note", "required": true}]',
        :'registrationQuestionID'
    )::jsonb,
    'Should return registration questions for pending users'
);

-- Should return registration questions and answers for confirmed attendees
select is(
    (
        list_user_events(:'questionsAttendeeUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'enrollment_status',
        'attendee',
        'has_paid_purchase',
        false,
        'registration_answers',
        format(
            '{"answers": [{"question_id": "%s", "value": "Attendee answer"}]}',
            :'registrationQuestionID'
        )::jsonb,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'roles',
        jsonb_build_array('attendee')
    ),
    'Should return registration questions and answers for confirmed attendees'
);

-- Should report active pending checkout before pending registration questions
select is(
    (
        list_user_events(:'questionsCheckoutUserID'::uuid, '{"limit": 10, "offset": 0}'::jsonb)::jsonb
        -> 'events'
        -> 0
    ) - 'event',
    jsonb_build_object(
        'amount_minor',
        1500,
        'currency_code',
        'USD',
        'enrollment_status',
        'pending-payment',
        'event_ticket_type_id',
        :'eventQuestionsTicketTypeID',
        'has_paid_purchase',
        false,
        'registration_answers',
        format(
            '{"answers": [{"question_id": "%s", "value": "Checkout answer"}]}',
            :'registrationQuestionID'
        )::jsonb,
        'registration_questions',
        get_event_registration_questions(:'communityID'::uuid, :'eventQuestionsID'::uuid)::jsonb,
        'resume_checkout_url',
        'https://example.test/checkout/resume',
        'roles',
        '[]'::jsonb,
        'ticket_title',
        'Questions admission'
    ),
    'Should report active pending checkout before pending registration questions'
);

-- Should omit expired checkout-backed pending registration
select is(
    list_user_events(
        :'questionsCheckoutExpiredUserID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should omit expired checkout-backed pending registration'
);

-- Should omit expired direct checkout without another participation role
select is(
    list_user_events(
        :'checkoutExpiredUserID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should omit expired direct checkout without another participation role'
);

-- Should hide an active offer from My Events while its refund is processing
select is(
    list_user_events(
        :'questionsRefundPendingUserID'::uuid,
        '{"limit": 10, "offset": 0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'events',
        '[]'::jsonb,
        'total',
        0
    ),
    'Should hide an active offer from My Events while its refund is processing'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
