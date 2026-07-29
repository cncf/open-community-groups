-- Tests declining owned admission offers from the user dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a160000-0000-0000-0000-000000000001'
\set eventCategoryID '4a160000-0000-0000-0000-000000000002'
\set eventID '4a160000-0000-0000-0000-000000000003'
\set groupCategoryID '4a160000-0000-0000-0000-000000000004'
\set groupID '4a160000-0000-0000-0000-000000000005'
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

-- Site providing the notification theme
insert into site (description, site_id, theme, title)
values (
    'Offer decline site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Offer Decline Site'
);

-- Community hosting the offer decline scenarios
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    :'communityID',
    'Offer decline tests',
    'Offer Decline Community',
    'https://example.com/logo.png',
    'offer-decline-community'
);

-- Group category used by the hosting group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Event category used by the ticketed event
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'General');

-- Organizer, offer recipients, and a non-owner user
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash-organizer', 'organizer@example.com', true, :'organizerID', 'organizer'),
    ('hash-recipient', 'recipient@example.com', true, :'recipientID', 'recipient'),
    ('hash-waitlist', 'waitlist@example.com', true, :'waitlistRecipientID', 'waitlist-recipient'),
    ('hash-wrong', 'wrong@example.com', true, :'wrongUserID', 'wrong-user');

-- Group hosting the ticketed event
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Offer Decline Group',
    'offer-decline-group'
);

-- Published ticketed event with offers to decline
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Offer decline event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Offer Decline Event',
    true,
    'offer-decline-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Ticket tier reserved by the pending offers
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventID',
    :'ticketTypeID',
    1,
    1,
    'General admission'
);

-- Free price window for the ticket tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    0,
    :'priceWindowID',
    :'ticketTypeID'
);

-- Pending approval and waitlist offers declined by the scenarios
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'offerID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'organizerID',
    'approval',
    'pending',
    :'recipientID'
), (
    :'waitlistOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    null,
    'waitlist',
    'pending',
    :'waitlistRecipientID'
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
    'P0001',
    'admission offer is no longer available',
    'Should reject declining another user''s offer'
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
        'group_id', :'groupID'::uuid,
        'non_ticketed_promoted_user_ids', '[]'::jsonb
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
            'recipient_name', 'recipient',
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

-- Should decline a waitlist-sourced offer without an organizer
select is(
    decline_event_admission_offer(
        :'waitlistRecipientID'::uuid,
        :'waitlistOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid,
        'non_ticketed_promoted_user_ids', '[]'::jsonb
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
