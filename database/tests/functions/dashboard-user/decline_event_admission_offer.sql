-- Tests declining owned admission offers from the user dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a160000-0000-0000-0000-000000000001'
\set discountCodeID '4a160000-0000-0000-0000-00000000000f'
\set eventCategoryID '4a160000-0000-0000-0000-000000000002'
\set eventID '4a160000-0000-0000-0000-000000000003'
\set expiredOfferID '4a160000-0000-0000-0000-000000000010'
\set expiredRecipientID '4a160000-0000-0000-0000-000000000011'
\set groupCategoryID '4a160000-0000-0000-0000-000000000004'
\set groupID '4a160000-0000-0000-0000-000000000005'
\set invitationOfferID '4a160000-0000-0000-0000-000000000012'
\set invitationRecipientID '4a160000-0000-0000-0000-000000000013'
\set linkedOfferID '4a160000-0000-0000-0000-000000000014'
\set linkedPurchaseID '4a160000-0000-0000-0000-000000000015'
\set linkedRecipientID '4a160000-0000-0000-0000-000000000016'
\set offerID '4a160000-0000-0000-0000-000000000006'
\set organizerID '4a160000-0000-0000-0000-000000000007'
\set priceWindowID '4a160000-0000-0000-0000-000000000008'
\set recipientID '4a160000-0000-0000-0000-000000000009'
\set siteID '4a160000-0000-0000-0000-00000000000c'
\set ticketTypeID '4a160000-0000-0000-0000-00000000000a'
\set terminalOfferID '4a160000-0000-0000-0000-000000000017'
\set terminalRecipientID '4a160000-0000-0000-0000-000000000018'
\set waitlistOfferID '4a160000-0000-0000-0000-00000000000d'
\set waitlistRecipientID '4a160000-0000-0000-0000-00000000000e'
\set wrongUserID '4a160000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, group categories, event categories and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'organizerID');
select fx_user(:'expiredRecipientID');
select fx_user(:'invitationRecipientID');
select fx_user(:'linkedRecipientID');
select fx_user(:'terminalRecipientID');
select fx_user(:'waitlistRecipientID');
select fx_user(:'wrongUserID');

-- Site providing the notification theme
insert into site (description, site_id, theme, title)
values (
    'Offer decline site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Offer Decline Site'
);

-- Organizer, offer recipients, and a non-owner user

select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-decline-event-admission-offer'));

-- Group hosting the ticketed event
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object('name', 'Offer Decline Group'));

-- Published ticketed event with offers to decline
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'name', 'Offer Decline Event',
    'published', true,
    'starts_at', current_timestamp + interval '1 day'
));

-- Ticket tier reserved by the pending offers
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Free price window for the ticket tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));

-- Pending approval and waitlist offers declined by the scenarios
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
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
    :'offerID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'approval',
    'pending',
    :'recipientID',

    null,
    null,
    null,
    null,
    null,
    null
), (
    :'waitlistOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    null,
    'waitlist',
    'pending',
    :'waitlistRecipientID',

    null,
    null,
    null,
    null,
    null,
    null
), (
    :'expiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    :'organizerID',
    'approval',
    'pending',
    :'expiredRecipientID',

    null,
    null,
    null,
    null,
    null,
    null
), (
    :'invitationOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'organizer_invitation',
    'pending',
    :'invitationRecipientID',

    null,
    null,
    null,
    null,
    null,
    null
), (
    :'linkedOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'organizer_invitation',
    'checkout_pending',
    :'linkedRecipientID',

    0,
    null,
    0,
    null,
    null,
    'General admission'
), (
    :'terminalOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'approval',
    'declined',
    :'terminalRecipientID',

    null,
    null,
    null,
    null,
    null,
    null
);

-- Discount reservation released with the linked checkout
insert into event_discount_code (
    active,
    amount_minor,
    available,
    available_override_active,
    code,
    event_discount_code_id,
    event_id,
    kind,
    title,
    total_available
) values (
    true,
    100,
    0,
    true,
    'LINKED',
    :'discountCodeID',
    :'eventID',
    'fixed_amount',
    'Linked checkout discount',
    1
);

-- Pending attendee answers held by the linked checkout
insert into event_attendee (event_id, registration_answers, status, user_id)
values (
    :'eventID',
    '{"answers": []}'::jsonb,
    'registration-questions-pending',
    :'linkedRecipientID'
);

-- Pending purchase linked to the declined organizer invitation
insert into event_purchase (
    admission_offer_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    discount_code,
    event_discount_code_id,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'linkedOfferID',
    0,
    'USD',
    100,
    'LINKED',
    :'discountCodeID',
    :'eventID',
    :'linkedPurchaseID',
    :'ticketTypeID',
    current_timestamp + interval '15 minutes',
    'pending',
    'General admission',
    :'linkedRecipientID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject declining another user's offer
select throws_ok(
    format(
        $$ select decline_event_admission_offer(%L, %L) $$,
        :'wrongUserID',
        :'offerID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject declining another user''s offer'
);

-- Should reject declining an expired offer
select throws_ok(
    format(
        $$ select decline_event_admission_offer(%L, %L) $$,
        :'expiredRecipientID',
        :'expiredOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject declining an expired offer'
);

-- Should reject declining a terminal offer
select throws_ok(
    format(
        $$ select decline_event_admission_offer(%L, %L) $$,
        :'terminalRecipientID',
        :'terminalOfferID'
    ),
    'OCG01',
    'admission offer is no longer available',
    'Should reject declining a terminal offer'
);

-- Should decline the owned ticket offer and return reconciliation context
select is(
    decline_event_admission_offer(
        :'recipientID'::uuid,
        :'offerID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should decline the owned ticket offer and return reconciliation context'
);

-- Should persist declined offer status
select is(
    (select status from admission_offer where admission_offer_id = :'offerID'),
    'declined',
    'Should persist declined offer status'
);

-- Should enqueue an organizer decline notification
select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-admission-offer-declined'
        and user_id = :'organizerID'
    ),
    1,
    'Should enqueue an organizer decline notification'
);

-- Should include declined offer context in the notification payload
select ok(
    (
        select ntd.data @> jsonb_build_object(
            'admission_offer_id', :'offerID',
            'dashboard_url', '/dashboard/group/events/' || :'eventID' || '/attendees',
            'event_id', :'eventID',
            'event_name', 'Offer Decline Event',
            'event_ticket_type_id', :'ticketTypeID',
            'group_name', 'Offer Decline Group',
            'recipient_name', 'recipient-decline-event-admission-offer',
            'theme', jsonb_build_object('primary_color', '#2563eb'),
            'ticket_title', 'General admission',
            'user_id', :'recipientID'
        )
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-declined'
        and n.user_id = :'organizerID'
    ),
    'Should include declined offer context in the notification payload'
);

-- Should audit the recipient decline
select results_eq(
    format(
        $$
        select action, actor_user_id, event_id, group_id, resource_id
        from audit_log
        where details->>'admission_offer_id' = %L
        $$,
        :'offerID'
    ),
    format(
        $$
        values (
            'event_admission_offer_declined'::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
        $$,
        :'recipientID',
        :'eventID',
        :'groupID',
        :'recipientID'
    ),
    'Should audit the recipient decline'
);

-- Should decline an organizer invitation
select is(
    decline_event_admission_offer(
        :'invitationRecipientID'::uuid,
        :'invitationOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should decline an organizer invitation'
);

-- Should audit an organizer invitation as rejected
select results_eq(
    format(
        $$
        select action, actor_user_id, event_id, group_id, resource_id
        from audit_log
        where details->>'admission_offer_id' = %L
        $$,
        :'invitationOfferID'
    ),
    format(
        $$
        values (
            'event_attendee_invitation_rejected'::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
        $$,
        :'invitationRecipientID',
        :'eventID',
        :'groupID',
        :'invitationRecipientID'
    ),
    'Should audit an organizer invitation as rejected'
);

-- Should decline an offer with a linked checkout
select is(
    decline_event_admission_offer(
        :'linkedRecipientID'::uuid,
        :'linkedOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should decline an offer with a linked checkout'
);

-- Should expire the linked checkout and release its reservations
select results_eq(
    format(
        $$
        select
            (select available from event_discount_code where event_discount_code_id = %L::uuid),
            (select hold_expires_at <= current_timestamp from event_purchase where event_purchase_id = %L::uuid),
            (select status from event_purchase where event_purchase_id = %L::uuid),
            (select count(*)::int from event_attendee where event_id = %L::uuid and user_id = %L::uuid)
        $$,
        :'discountCodeID',
        :'linkedPurchaseID',
        :'linkedPurchaseID',
        :'eventID',
        :'linkedRecipientID'
    ),
    $$ values (1, true, 'expired'::text, 0::int) $$,
    'Should expire the linked checkout and release its reservations'
);

-- Should decline a waitlist-sourced offer without an organizer
select is(
    decline_event_admission_offer(
        :'waitlistRecipientID'::uuid,
        :'waitlistOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should decline a waitlist-sourced offer without an organizer'
);

-- Should persist declined waitlist offer status
select is(
    (select status from admission_offer where admission_offer_id = :'waitlistOfferID'),
    'declined',
    'Should persist declined waitlist offer status'
);

-- Should skip organizer notifications for waitlist-sourced offers
select is(
    (
        select count(*)::int
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-declined'
        and (ntd.data->>'admission_offer_id')::uuid = :'waitlistOfferID'::uuid
    ),
    0,
    'Should skip organizer notifications for waitlist-sourced offers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
