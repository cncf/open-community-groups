-- Tests returning public full event information.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(6);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeOfferID '0c160000-0000-0000-0000-00000000000d'
\set activeOfferUserID '0c160000-0000-0000-0000-00000000000e'
\set activeHoldUserID '0c160000-0000-0000-0000-00000000000f'
\set communityID '0c160000-0000-0000-0000-000000000001'
\set completedPurchaseUserID '0c160000-0000-0000-0000-000000000010'
\set eventCategoryID '0c160000-0000-0000-0000-000000000002'
\set eventID '0c160000-0000-0000-0000-000000000003'
\set eventPrivateID '0c160000-0000-0000-0000-00000000000a'
\set expiredHoldUserID '0c160000-0000-0000-0000-000000000011'
\set expiredOfferID '0c160000-0000-0000-0000-000000000012'
\set expiredOfferUserID '0c160000-0000-0000-0000-000000000013'
\set futurePublicTicketTypeID '0c160000-0000-0000-0000-000000000017'
\set futurePublicWindowID '0c160000-0000-0000-0000-000000000018'
\set groupCategoryID '0c160000-0000-0000-0000-000000000004'
\set groupID '0c160000-0000-0000-0000-000000000005'
\set inactivePublicTicketTypeID '0c160000-0000-0000-0000-000000000015'
\set inactivePublicWindowID '0c160000-0000-0000-0000-000000000016'
\set pendingRequestUserID '0c160000-0000-0000-0000-000000000014'
\set privateOnlyTicketTypeID '0c160000-0000-0000-0000-00000000000b'
\set privateOnlyWindowID '0c160000-0000-0000-0000-00000000000c'
\set privateTicketTypeID '0c160000-0000-0000-0000-000000000006'
\set privateWindowID '0c160000-0000-0000-0000-000000000007'
\set publicTicketTypeID '0c160000-0000-0000-0000-000000000008'
\set publicWindowID '0c160000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community for public full event scenarios
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
    'public-event-community',
    'Public Event Community',
    'Community for public full event tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category for public full event scenarios
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category for public full event scenarios
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group for public full event scenarios
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Public Event Group',
    'public-event-group'
);

-- Users covering public inventory allocation and exclusion states
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (
        :'activeOfferUserID',
        'active-offer-hash',
        'active-offer@example.test',
        true,
        'active-offer-user'
    ),
    (
        :'activeHoldUserID',
        'active-hold-hash',
        'active-hold@example.test',
        true,
        'active-hold-user'
    ),
    (
        :'completedPurchaseUserID',
        'completed-purchase-hash',
        'completed-purchase@example.test',
        true,
        'completed-purchase-user'
    ),
    (
        :'expiredHoldUserID',
        'expired-hold-hash',
        'expired-hold@example.test',
        true,
        'expired-hold-user'
    ),
    (
        :'expiredOfferUserID',
        'expired-offer-hash',
        'expired-offer@example.test',
        true,
        'expired-offer-user'
    ),
    (
        :'pendingRequestUserID',
        'pending-request-hash',
        'pending-request@example.test',
        true,
        'pending-request-user'
    );

-- Events with mixed and fully invitation-only ticket inventory
insert into event (
    event_id,
    capacity,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    payment_currency_code,
    published,
    slug,
    timezone
) values
    (
        :'eventID',
        65,
        'Event for public full event tests',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Public Event',
        'USD',
        true,
        'public-event',
        'UTC'
    ),
    (
        :'eventPrivateID',
        5,
        'Fully private event for public full event tests',
        :'eventCategoryID',
        'virtual',
        :'groupID',
        'Private Event',
        'USD',
        true,
        'private-event',
        'UTC'
    );

-- Public and invitation-only ticket types
insert into event_ticket_type (
    event_ticket_type_id,
    active,
    availability,
    event_id,
    "order",
    seats_total,
    title
) values
    (
        :'publicTicketTypeID',
        true,
        'public',
        :'eventID',
        1,
        10,
        'Public pass'
    ),
    (
        :'privateTicketTypeID',
        true,
        'invitation_only',
        :'eventID',
        2,
        5,
        'Private pass'
    ),
    (
        :'inactivePublicTicketTypeID',
        false,
        'public',
        :'eventID',
        3,
        20,
        'Inactive public pass'
    ),
    (
        :'futurePublicTicketTypeID',
        true,
        'public',
        :'eventID',
        4,
        30,
        'Future public pass'
    ),
    (
        :'privateOnlyTicketTypeID',
        true,
        'invitation_only',
        :'eventPrivateID',
        1,
        5,
        'Private-only pass'
    );

-- Current and future prices for public and invitation-only ticket types
insert into event_ticket_price_window (
    event_ticket_price_window_id,
    amount_minor,
    event_ticket_type_id,
    starts_at
) values
    (
        :'futurePublicWindowID',
        2500,
        :'futurePublicTicketTypeID',
        current_timestamp + interval '1 day'
    ),
    (:'inactivePublicWindowID', 2500, :'inactivePublicTicketTypeID', null),
    (:'privateOnlyWindowID', 5000, :'privateOnlyTicketTypeID', null),
    (:'privateWindowID', 5000, :'privateTicketTypeID', null),
    (:'publicWindowID', 2500, :'publicTicketTypeID', null);

-- Active and expired organizer invitations for public inventory
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'activeOfferID',
        current_timestamp,
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp + interval '1 hour',
        'organizer_invitation',
        'pending',
        :'activeOfferUserID'
    ),
    (
        :'expiredOfferID',
        current_timestamp - interval '2 hours',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp - interval '1 hour',
        'organizer_invitation',
        'pending',
        :'expiredOfferUserID'
    );

-- Pending invitation request awaiting organizer approval
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    status,
    user_id
) values (
    :'eventID',
    :'publicTicketTypeID',
    'pending',
    :'pendingRequestUserID'
);

-- Completed purchase plus active and expired checkout holds
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        null,
        'completed',
        'Public pass',
        :'completedPurchaseUserID'
    ),
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp + interval '1 hour',
        'pending',
        'Public pass',
        :'activeHoldUserID'
    ),
    (
        0,
        'USD',
        :'eventID',
        :'publicTicketTypeID',
        current_timestamp - interval '1 hour',
        'pending',
        'Public pass',
        :'expiredHoldUserID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should calculate capacity from visible public ticket inventory
select is(
    (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb->>'capacity'
    )::int,
    10,
    'Should calculate capacity from visible public ticket inventory'
);

-- Should calculate remaining capacity from canonical public ticket allocations
select is(
    (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventID'::uuid
        )::jsonb->>'remaining_capacity'
    )::int,
    7,
    'Should calculate remaining capacity from canonical public ticket allocations'
);

-- Should keep organizer inventory across all ticket types unchanged
select is(
    jsonb_build_object(
        'capacity', organizer_event->'capacity',
        'remaining_capacity', organizer_event->'remaining_capacity'
    ),
    jsonb_build_object(
        'capacity', 65,
        'remaining_capacity', 62
    ),
    'Should keep organizer inventory across all ticket types unchanged'
)
from (
    select get_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb as organizer_event
) organizer_event_projection;

-- Should omit public inventory for fully invitation-only events
select ok(
    not (private_event ? 'capacity')
    and not (private_event ? 'remaining_capacity')
    and not (private_event ? 'ticket_types'),
    'Should omit public inventory for fully invitation-only events'
)
from (
    select get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventPrivateID'::uuid
    )::jsonb as private_event
) private_event_projection;

-- Should remove the superseded ticketed enrollment flag
select ok(
    not (
        get_public_event_full(
            :'communityID'::uuid,
            :'groupID'::uuid,
            :'eventPrivateID'::uuid
        )::jsonb ? 'is_ticketed'
    ),
    'Should remove the superseded ticketed enrollment flag'
);

-- Should replace organizer ticket inventory with the public projection
select is(
    (get_public_event_full(
        :'communityID'::uuid,
        :'groupID'::uuid,
        :'eventID'::uuid
    )::jsonb)->'ticket_types',
    list_public_event_ticket_types(:'eventID'::uuid),
    'Should replace organizer ticket inventory with the public projection'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
