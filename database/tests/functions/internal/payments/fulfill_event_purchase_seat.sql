-- Tests fulfilling the seat of a purchase being completed locally.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(11);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventPurchaseID 'e7b20000-0000-0000-0000-000000000001'
\set communityID 'e7b20000-0000-0000-0000-000000000002'
\set completedOfferID 'e7b20000-0000-0000-0000-000000000003'
\set completedOfferPurchaseID 'e7b20000-0000-0000-0000-000000000004'
\set eventCanceledID 'e7b20000-0000-0000-0000-000000000005'
\set eventCanceledTicketTypeID 'e7b20000-0000-0000-0000-000000000006'
\set eventCategoryID 'e7b20000-0000-0000-0000-000000000007'
\set eventID 'e7b20000-0000-0000-0000-000000000008'
\set eventStartedID 'e7b20000-0000-0000-0000-000000000009'
\set eventStartedTicketTypeID 'e7b20000-0000-0000-0000-000000000010'
\set eventTicketTypeID 'e7b20000-0000-0000-0000-000000000011'
\set expiredHoldPurchaseID 'e7b20000-0000-0000-0000-000000000012'
\set groupCategoryID 'e7b20000-0000-0000-0000-000000000013'
\set groupID 'e7b20000-0000-0000-0000-000000000014'
\set invitationOfferID 'e7b20000-0000-0000-0000-000000000015'
\set invitationPurchaseID 'e7b20000-0000-0000-0000-000000000016'
\set invitedPurchaseID 'e7b20000-0000-0000-0000-000000000017'
\set plainPurchaseID 'e7b20000-0000-0000-0000-000000000018'
\set recoveryPurchaseID 'e7b20000-0000-0000-0000-000000000019'
\set recoveryReplacementPurchaseID 'e7b20000-0000-0000-0000-000000000020'
\set startedEventPurchaseID 'e7b20000-0000-0000-0000-000000000021'
\set user1ID 'e7b20000-0000-0000-0000-000000000022'
\set user2ID 'e7b20000-0000-0000-0000-000000000023'
\set user3ID 'e7b20000-0000-0000-0000-000000000024'
\set user4ID 'e7b20000-0000-0000-0000-000000000025'
\set user5ID 'e7b20000-0000-0000-0000-000000000026'
\set user6ID 'e7b20000-0000-0000-0000-000000000027'
\set user7ID 'e7b20000-0000-0000-0000-000000000028'
\set user8ID 'e7b20000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community that owns the group
select fx_community(:'communityID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Buyer of the purchase whose hold expired
select fx_user(:'user1ID');

-- Buyer whose earlier purchase awaits refund recovery
select fx_user(:'user2ID');

-- Buyer of the purchase on the canceled event
select fx_user(:'user3ID');

-- Holder of the already completed offer
select fx_user(:'user4ID');

-- Buyer with a pending invitation that checkout cannot confirm
select fx_user(:'user5ID');

-- Organizer-invited buyer whose canceled attendance is revived
select fx_user(:'user6ID');

-- Buyer of the purchase without an offer
select fx_user(:'user7ID');

-- Buyer of the purchase on the started event
select fx_user(:'user8ID');

-- Active group that owns the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('active', true));

-- Published future event accepting enrollment
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event that was canceled
select fx_event(:'eventCanceledID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'published', true,
    'published_at', current_timestamp,
    'starts_at', current_timestamp + interval '1 day'
));

-- Published event that started and has not ended, with an open-only registration window
select fx_event(:'eventStartedID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp + interval '1 hour',
    'published', true,
    'published_at', current_timestamp,
    'registration_starts_at', current_timestamp - interval '2 hours',
    'starts_at', current_timestamp - interval '1 hour'
));

-- Ticket type of the canceled event
select fx_event_ticket_type(:'eventCanceledTicketTypeID', :'eventCanceledID');

-- Ticket type of the started event
select fx_event_ticket_type(:'eventStartedTicketTypeID', :'eventStartedID');

-- Ticket type of the future event
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID');

-- Canceled attendance revived by the organizer invitation purchase, inserted
-- before its offer because active offers reject new attendee rows
insert into event_attendee (
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    event_id,
    status,
    user_id
) values (
    current_timestamp,
    :'user6ID',
    :'eventID',
    'attendance-canceled',
    :'user6ID'
);

-- Pending invitation that checkout cannot confirm
insert into event_attendee (event_id, manually_invited, status, user_id)
values (:'eventID', true, 'invitation-pending', :'user5ID');

-- Offer that already reached its terminal completed state
insert into admission_offer (
    admission_offer_id,
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
) values (
    :'completedOfferID',
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '1 hour',
    'waitlist',
    'completed',
    :'user4ID',

    0,
    null,
    0,
    null,
    null,
    'General admission'
);

-- Checkout-pending organizer invitation completed by the success scenario
insert into admission_offer (
    admission_offer_id,
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
) values (
    :'invitationOfferID',
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'checkout_pending',
    :'user6ID',

    0,
    null,
    0,
    null,
    null,
    'General admission'
);

-- Pending purchase on the canceled event
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'canceledEventPurchaseID',
    0,
    :'eventCanceledID',
    :'eventCanceledTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user3ID'
);

-- Pending purchase linked to the completed offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'completedOfferPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user4ID',

    :'completedOfferID'
);

-- Pending purchase whose hold expired
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'expiredHoldPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'user1ID'
);

-- Pending purchase that claims the organizer invitation
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'invitationPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user6ID',

    :'invitationOfferID'
);

-- Pending purchase of the user whose invitation is still pending
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'invitedPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user5ID'
);

-- Pending purchase without an offer
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'plainPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user7ID'
);

-- Refunded paid purchase whose terminal provider failure requires recovery
insert into event_purchase (
    event_purchase_id,
    amount_minor,
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
    venue_snapshot,

    charge_model,
    connected_seller_id
) values (
    :'recoveryPurchaseID',
    2500,
    'USD',
    :'eventID',
    :'eventTicketTypeID',
    0,
    'stripe',
    'ch_fulfill_seat_recovery',
    'cs_fulfill_seat_recovery',
    'acct_fulfill_seat',
    'pi_fulfill_seat_recovery',
    2500,
    '{"connected_account_id":"acct_fulfill_seat","display_name":"Sponsor","provider":"stripe"}'::jsonb,
    'refund-recovery-pending',
    2500,
    0,
    'inclusive',
    'manual',
    'professional-event-admission',
    'General admission',
    :'user2ID',
    '{}'::jsonb,

    'direct-charge',
    'acct_fulfill_seat'
);

-- Pending free replacement created before the original refund failed
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'recoveryReplacementPurchaseID',
    0,
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user2ID'
);

-- Pending purchase on the started event
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'startedEventPurchaseID',
    0,
    :'eventStartedID',
    :'eventStartedTicketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'user8ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should accept a started event whose open-only registration window closed at its start
select lives_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'startedEventPurchaseID'
    ),
    'Should accept a started event whose open-only registration window closed at its start'
);

select is(
    (
        select status
        from event_attendee
        where event_id = :'eventStartedID'::uuid
        and user_id = :'user8ID'::uuid
    ),
    'confirmed',
    'Should accept a started event whose open-only registration window closed at its start'
);

-- Should complete the offer and confirm an organizer-invited attendee
select lives_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'invitationPurchaseID'
    ),
    'Should complete the offer and confirm an organizer-invited attendee'
);

select results_eq(
    format(
        $$
            select
                ea.attendance_canceled_at,
                ea.attendance_canceled_by_user_id,
                ea.manually_invited,
                ea.status,
                ao.status
            from event_attendee ea
            join admission_offer ao on ao.event_id = ea.event_id
                and ao.user_id = ea.user_id
            where ao.admission_offer_id = %L::uuid
        $$,
        :'invitationOfferID'
    ),
    $$ values (null::timestamptz, null::uuid, true, 'confirmed'::text, 'completed'::text) $$,
    'Should complete the offer and confirm an organizer-invited attendee'
);

-- Should confirm an attendee without an offer as not manually invited
select lives_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'plainPurchaseID'
    ),
    'Should confirm an attendee without an offer as not manually invited'
);

select results_eq(
    format(
        $$
            select manually_invited, status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'user7ID'
    ),
    $$ values (false, 'confirmed'::text) $$,
    'Should confirm an attendee without an offer as not manually invited'
);

-- Should reject attendees that cannot be confirmed
select throws_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'invitedPurchaseID'
    ),
    'OCG01',
    'attendee cannot be confirmed for this event',
    'Should reject attendees that cannot be confirmed'
);

-- Should reject events that no longer accept enrollment
select throws_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'canceledEventPurchaseID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events that no longer accept enrollment'
);

-- Should reject expired holds
select throws_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'expiredHoldPurchaseID'
    ),
    'OCG01',
    'purchase hold has expired',
    'Should reject expired holds'
);

-- Should reject offers that are no longer checkout pending
select throws_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'completedOfferPurchaseID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject offers that are no longer checkout pending'
);

-- Should reject purchases while another purchase awaits refund recovery
select throws_ok(
    format(
        $$
            select fulfill_event_purchase_seat(ep, e, g, ao)
            from event_purchase ep
            join event e on e.event_id = ep.event_id
            join "group" g on g.group_id = e.group_id
            left join admission_offer ao on ao.admission_offer_id = ep.admission_offer_id
            where ep.event_purchase_id = %L::uuid
        $$,
        :'recoveryReplacementPurchaseID'
    ),
    'OCG01',
    'checkout is unavailable while refund recovery is in progress',
    'Should reject purchases while another purchase awaits refund recovery'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
