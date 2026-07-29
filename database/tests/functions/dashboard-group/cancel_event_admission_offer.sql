-- Tests canceling active admission offers from the group dashboard.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID '4a150000-0000-0000-0000-000000000001'
\set approvalOfferID '4a150000-0000-0000-0000-00000000000d'
\set approvalRecipientID '4a150000-0000-0000-0000-00000000000e'
\set communityID '4a150000-0000-0000-0000-000000000002'
\set eventCategoryID '4a150000-0000-0000-0000-000000000003'
\set eventID '4a150000-0000-0000-0000-000000000004'
\set groupCategoryID '4a150000-0000-0000-0000-000000000005'
\set groupID '4a150000-0000-0000-0000-000000000006'
\set offerID '4a150000-0000-0000-0000-000000000007'
\set priceWindowID '4a150000-0000-0000-0000-000000000008'
\set recipientID '4a150000-0000-0000-0000-000000000009'
\set siteID '4a150000-0000-0000-0000-00000000000c'
\set ticketTypeID '4a150000-0000-0000-0000-00000000000a'
\set unknownGroupID '4a150000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Site
insert into site (description, site_id, theme, title)
values (
    'Offer cancellation site',
    :'siteID',
    '{"primary_color": "#2563eb"}'::jsonb,
    'Offer Cancellation Site'
);

-- Community
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
    'Offer cancellation tests',
    'Offer Cancellation Community',
    'https://example.com/logo.png',
    'offer-cancellation-community'
);

-- Group category
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Event category
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'General');

-- Users: organizer actor and both offer recipients
insert into "user" (auth_hash, email, email_verified, user_id, username)
values
    ('hash-actor', 'actor@example.com', true, :'actorID', 'actor'),
    ('hash-approval', 'approval@example.com', true, :'approvalRecipientID', 'approval-recipient'),
    ('hash-recipient', 'recipient@example.com', true, :'recipientID', 'recipient');

-- Group
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (
    :'communityID',
    :'groupCategoryID',
    :'groupID',
    'Offer Cancellation Group',
    'offer-cancellation-group'
);

-- Published event
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
    'Offer cancellation event',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Offer Cancellation Event',
    true,
    'offer-cancellation-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Invitation-only single-seat ticket type
insert into event_ticket_type (
    availability,
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    'invitation_only',
    :'eventID',
    :'ticketTypeID',
    1,
    1,
    'Private admission'
);

-- Free price window for the ticket type
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    0,
    :'priceWindowID',
    :'ticketTypeID'
);

-- Pending organizer-invitation and approval offers to cancel
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
    :'actorID',
    'organizer_invitation',
    'pending',
    :'recipientID'
), (
    :'approvalOfferID',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    :'actorID',
    'approval',
    'pending',
    :'approvalRecipientID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject offers outside the selected group
select throws_ok(
    format(
        $$ select cancel_event_admission_offer(%L, %L, %L) $$,
        :'actorID',
        :'unknownGroupID',
        :'offerID'
    ),
    'P0001',
    'admission offer is no longer available',
    'Should reject offers outside the selected group'
);

-- Should cancel a group-scoped ticket offer and return reconciliation context
select is(
    cancel_event_admission_offer(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'offerID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid,
        'non_ticketed_promoted_user_ids', '[]'::jsonb
    ),
    'Should cancel a group-scoped ticket offer and return reconciliation context'
);

-- Should persist canceled offer status
select is(
    (select status from admission_offer where admission_offer_id = :'offerID'),
    'canceled',
    'Should persist canceled offer status'
);

-- Should enqueue a recipient cancellation notification
select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-admission-offer-canceled'
        and user_id = :'recipientID'
    ),
    1,
    'Should enqueue a recipient cancellation notification'
);

-- Should include canceled offer context in the notification payload
select is(
    (
        select ntd.data
        from notification n
        join notification_template_data ntd using (notification_template_data_id)
        where n.kind = 'event-admission-offer-canceled'
        and n.user_id = :'recipientID'
    ),
    jsonb_build_object(
        'admission_offer_id', :'offerID',
        'dashboard_url', '/dashboard/user?tab=events',
        'event_id', :'eventID',
        'event_name', 'Offer Cancellation Event',
        'event_ticket_type_id', :'ticketTypeID',
        'group_name', 'Offer Cancellation Group',
        'theme', jsonb_build_object('primary_color', '#2563eb'),
        'ticket_title', 'Private admission',
        'user_id', :'recipientID'
    ),
    'Should include canceled offer context in the notification payload'
);

-- Should audit the organizer cancellation
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
            'event_attendee_invitation_canceled'::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
        $$,
        :'actorID',
        :'eventID',
        :'groupID',
        :'recipientID'
    ),
    'Should audit the organizer cancellation'
);

-- Should cancel an approval-sourced offer and return reconciliation context
select is(
    cancel_event_admission_offer(
        :'actorID'::uuid,
        :'groupID'::uuid,
        :'approvalOfferID'::uuid
    )::jsonb,
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid,
        'group_id', :'groupID'::uuid,
        'non_ticketed_promoted_user_ids', '[]'::jsonb
    ),
    'Should cancel an approval-sourced offer and return reconciliation context'
);

-- Should notify the approval recipient after cancellation
select is(
    (
        select count(*)::int
        from notification
        where kind = 'event-admission-offer-canceled'
        and user_id = :'approvalRecipientID'
    ),
    1,
    'Should notify the approval recipient after cancellation'
);

-- Should audit approval-sourced offer cancellation distinctly
select results_eq(
    format(
        $$
        select action, actor_user_id, event_id, group_id, resource_id
        from audit_log
        where details->>'admission_offer_id' = %L
        $$,
        :'approvalOfferID'
    ),
    format(
        $$
        values (
            'event_admission_offer_canceled'::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            %L::uuid
        )
        $$,
        :'actorID',
        :'eventID',
        :'groupID',
        :'approvalRecipientID'
    ),
    'Should audit approval-sourced offer cancellation distinctly'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
