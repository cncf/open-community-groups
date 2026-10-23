-- Tests declining owned admission offers from the user dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a160000-0000-0000-0000-000000000001'
\set eventCategoryID '4a160000-0000-0000-0000-000000000002'
\set eventID '4a160000-0000-0000-0000-000000000003'
\set expiredOfferID '4a160000-0000-0000-0000-000000000010'
\set expiredRecipientID '4a160000-0000-0000-0000-000000000011'
\set filteredOfferID '4a160000-0000-0000-0000-000000000019'
\set filteredOrganizerID '4a160000-0000-0000-0000-00000000001a'
\set filteredRecipientID '4a160000-0000-0000-0000-00000000001b'
\set groupCategoryID '4a160000-0000-0000-0000-000000000004'
\set groupID '4a160000-0000-0000-0000-000000000005'
\set invitationOfferID '4a160000-0000-0000-0000-000000000012'
\set invitationRecipientID '4a160000-0000-0000-0000-000000000013'
\set offerID '4a160000-0000-0000-0000-000000000006'
\set organizerID '4a160000-0000-0000-0000-000000000007'
\set priceWindowID '4a160000-0000-0000-0000-000000000008'
\set recipientID '4a160000-0000-0000-0000-000000000009'
\set siteID '4a160000-0000-0000-0000-00000000000c'
\set ticketTypeID '4a160000-0000-0000-0000-00000000000a'
\set waitlistOfferID '4a160000-0000-0000-0000-00000000000d'
\set waitlistRecipientID '4a160000-0000-0000-0000-00000000000e'
\set wrongUserID '4a160000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the event group
select fx_community(:'communityID');

-- Site providing the notification theme
insert into site (description, site_id, theme, title)
values (
    'Offer decline site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Offer Decline Site'
);

-- Recipient of the expired offer
select fx_user(:'expiredRecipientID');

-- Organizer opted out of attendee activity notifications
select fx_user(:'filteredOrganizerID');

-- Recipient of the offer assigned by the opted-out organizer
select fx_user(:'filteredRecipientID');

-- Recipient of the organizer invitation
select fx_user(:'invitationRecipientID');

-- Organizer assigning the approval and invitation offers
select fx_user(:'organizerID');

-- Recipient of the approval offer
select fx_user(:'recipientID', jsonb_build_object('username', 'recipient-decline-event-admission-offer'));

-- Recipient of the waitlist offer
select fx_user(:'waitlistRecipientID');

-- User who does not own the approval offer
select fx_user(:'wrongUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Attendee activity opt-out used by a filtered organizer notification scenario
insert into user_notification_opt_out (notification_category_id, user_id)
values ('attendee-activity', :'filteredOrganizerID');

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

-- Pending approval, invitation and waitlist offers and an expired offer
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'offerID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'approval',
    'pending',
    :'recipientID'
), (
    :'filteredOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'filteredOrganizerID',
    'approval',
    'pending',
    :'filteredRecipientID'
), (
    :'waitlistOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    null,
    'waitlist',
    'pending',
    :'waitlistRecipientID'
), (
    :'expiredOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '1 hour',
    :'organizerID',
    'approval',
    'pending',
    :'expiredRecipientID'
), (
    :'invitationOfferID',
    current_timestamp,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'organizer_invitation',
    'pending',
    :'invitationRecipientID'
);

-- Free price window for the ticket tier
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));

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
            'dashboard_url', '/dashboard/group?tab=events',
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

-- Should decline an offer whose organizer opted out of attendee activity
select is(
    decline_event_admission_offer(
        :'filteredRecipientID'::uuid,
        :'filteredOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid
    ),
    'Should decline an offer whose organizer opted out of attendee activity'
);

-- Should store the decline without notifying the opted-out organizer
select ok(
    (select status from admission_offer where admission_offer_id = :'filteredOfferID') = 'declined'
    and not exists (
        select 1
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-declined'
        and n.user_id = :'filteredOrganizerID'
        and (ntd.data->>'admission_offer_id')::uuid = :'filteredOfferID'
    ),
    'Should store the decline without notifying the opted-out organizer'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
