-- Tests listing active event admission offers owned by a user.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set acceptedUserID '4a0b0000-0000-0000-0000-000000000001'
\set canceledEventID '4a0b0000-0000-0000-0000-000000000002'
\set communityID '4a0b0000-0000-0000-0000-000000000003'
\set eventCategoryID '4a0b0000-0000-0000-0000-000000000004'
\set eventID '4a0b0000-0000-0000-0000-000000000005'
\set eventTicketedID '4a0b0000-0000-0000-0000-000000000012'
\set groupCategoryID '4a0b0000-0000-0000-0000-000000000006'
\set groupID '4a0b0000-0000-0000-0000-000000000007'
\set inactiveGroupEventID '4a0b0000-0000-0000-0000-000000000008'
\set inactiveGroupID '4a0b0000-0000-0000-0000-000000000009'
\set invitedUserID '4a0b0000-0000-0000-0000-000000000010'
\set invitedOfferID '4a0b0000-0000-0000-0000-000000000013'
\set priceWindowID '4a0b0000-0000-0000-0000-000000000014'
\set questionID '4a0b0000-0000-0000-0000-00000000001c'
\set rejectedUserID '4a0b0000-0000-0000-0000-000000000011'
\set ticketOfferID '4a0b0000-0000-0000-0000-000000000015'
\set ticketPurchaseID '4a0b0000-0000-0000-0000-00000000001d'
\set ticketTypeID '4a0b0000-0000-0000-0000-000000000016'
\set ticketUserID '4a0b0000-0000-0000-0000-000000000017'

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
    'event-invitations-community',
    'Event Invitations Community',
    'Community for testing event invitation listings',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Group category
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Event category
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'General');

-- Users
insert into "user" (
    user_id,
    auth_hash,
    email,
    email_verified,
    username,
    name
) values (
    :'invitedUserID',
    'hash-invited',
    'invited@example.com',
    true,
    'invited',
    'Invited User'
), (
    :'acceptedUserID',
    'hash-accepted',
    'accepted@example.com',
    true,
    'accepted',
    'Accepted User'
), (
    :'rejectedUserID',
    'hash-rejected',
    'rejected@example.com',
    true,
    'rejected',
    'Rejected User'
), (
    :'ticketUserID',
    'hash-ticket',
    'ticket@example.com',
    true,
    'ticket-user',
    'Ticket User'
);

-- Groups
insert into "group" (group_id, community_id, group_category_id, name, slug, active)
values
    (:'groupID', :'communityID', :'groupCategoryID', 'Event Invitations Group', 'events', true),
    (:'inactiveGroupID', :'communityID', :'groupCategoryID', 'Inactive Group', 'inactive', false);

-- Events
insert into event (
    event_id,
    name,
    slug,
    description,
    timezone,
    event_category_id,
    event_kind_id,
    group_id,
    payment_currency_code,
    published,
    canceled,
    registration_questions,
    starts_at
) values (
    :'eventID',
    'Future Event',
    'future-event',
    'Future event with pending invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    '[]'::jsonb,
    '2099-01-02 10:00:00+00'
), (
    :'canceledEventID',
    'Canceled Event',
    'canceled-event',
    'Canceled event with ignored invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    true,
    '[]'::jsonb,
    '2099-01-03 10:00:00+00'
), (
    :'eventTicketedID',
    'Ticket Event',
    'ticket-event',
    'Ticket event with an approval offer',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'USD',
    true,
    false,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Meal", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    '2099-01-05 10:00:00+00'
), (
    :'inactiveGroupEventID',
    'Inactive Group Event',
    'inactive-event',
    'Inactive group event with ignored invitations',
    'UTC',
    :'eventCategoryID',
    'in-person',
    :'inactiveGroupID',
    'USD',
    true,
    false,
    '[]'::jsonb,
    '2099-01-04 10:00:00+00'
);

-- Ticket tier assigned by the approval offer
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'eventTicketedID',
    :'ticketTypeID',
    1,
    10,
    'General admission'
);

-- Paid price window for the ticket tier
insert into event_ticket_price_window (
    amount_minor,
    event_ticket_price_window_id,
    event_ticket_type_id
) values (
    1000,
    :'priceWindowID',
    :'ticketTypeID'
);

-- Event invitation offer states
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
)
values
    (
        :'invitedOfferID',
        null,
        '2024-01-02 10:00:00+00',
        null,
        null,
        :'eventID',
        null,
        '2099-01-02 10:00:00+00',
        'organizer_invitation',
        'pending',
        null,
        :'invitedUserID'
    ),
    (
        '4a0b0000-0000-0000-0000-000000000018',
        null,
        '2024-01-03 10:00:00+00',
        null,
        null,
        :'canceledEventID',
        null,
        '2099-01-03 10:00:00+00',
        'organizer_invitation',
        'pending',
        null,
        :'invitedUserID'
    ),
    (
        '4a0b0000-0000-0000-0000-000000000019',
        null,
        '2024-01-04 10:00:00+00',
        null,
        null,
        :'inactiveGroupEventID',
        null,
        '2099-01-04 10:00:00+00',
        'organizer_invitation',
        'pending',
        null,
        :'invitedUserID'
    ),
    (
        '4a0b0000-0000-0000-0000-00000000001a',
        null,
        '2024-01-05 10:00:00+00',
        null,
        null,
        :'eventID',
        null,
        '2099-01-05 10:00:00+00',
        'organizer_invitation',
        'completed',
        null,
        :'acceptedUserID'
    ),
    (
        '4a0b0000-0000-0000-0000-00000000001b',
        null,
        '2024-01-06 10:00:00+00',
        null,
        null,
        :'eventID',
        null,
        '2099-01-06 10:00:00+00',
        'organizer_invitation',
        'declined',
        null,
        :'rejectedUserID'
    ),
    (
        :'ticketOfferID',
        1000,
        '2024-01-07 10:00:00+00',
        'USD',
        0,
        :'eventTicketedID',
        :'ticketTypeID',
        '2099-01-05 10:00:00+00',
        'approval',
        'checkout_pending',
        'General admission',
        :'ticketUserID'
    );

-- Accepted ticket request that supplies claim-time registration answers
insert into event_invitation_request (
    event_id,
    user_id,
    status,
    registration_answers,
    reviewed_at,
    reviewed_by
) values (
    :'eventTicketedID',
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
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    provider_checkout_url,
    status,
    ticket_title,
    user_id,

    admission_offer_id
) values (
    :'ticketPurchaseID',
    1000,
    'USD',
    :'eventTicketedID',
    :'ticketTypeID',
    '2099-01-05 09:00:00+00',
    'https://example.test/checkout/resume',
    'pending',
    'General admission',
    :'ticketUserID',

    :'ticketOfferID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list active pending event invitations for a user.
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
                    "expires_at": 4071031200,
                    "registration_questions": [],
                    "starts_at": 4071031200
                }
            ]
        $json$,
        :'invitedOfferID', :'eventID'
    )::jsonb,
    'Should list active pending event invitations for the user'
);

-- Should expose the exact assigned tier on an owned ticket offer.
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
                    "registration_answers": {
                        "answers": [
                            {
                                "question_id": "4a0b0000-0000-0000-0000-00000000001c",
                                "value": "Vegetarian"
                            }
                        ]
                    },
                    "registration_questions": [
                        {
                            "id": "4a0b0000-0000-0000-0000-00000000001c",
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
        :'ticketOfferID', :'eventTicketedID', :'ticketTypeID'
    )::jsonb,
    'Should expose the exact assigned tier on an owned ticket offer'
);

-- Automatic refunds keep the ticket offer unavailable until they finish
update event_purchase
set status = 'refund-pending'
where event_purchase_id = :'ticketPurchaseID';

select is(
    list_user_event_invitations(:'ticketUserID'::uuid)::text,
    '[]',
    'Should hide ticket offers while their automatic refund is pending'
);

-- Should not list accepted event invitations.
select is(
    list_user_event_invitations(:'acceptedUserID'::uuid)::text,
    '[]',
    'Should not list accepted event invitations'
);

-- Should not list rejected event invitations.
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
