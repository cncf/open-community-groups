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

-- Baseline communities, group categories, event categories, users and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'activeOfferUserID');
select fx_user(:'activeHoldUserID');
select fx_user(:'completedPurchaseUserID');
select fx_user(:'expiredHoldUserID');
select fx_user(:'expiredOfferUserID');
select fx_user(:'pendingRequestUserID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events with mixed and fully invitation-only ticket inventory
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 65,
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true
));
select fx_event(:'eventPrivateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 5,
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD',
    'published', true
));

-- Public and invitation-only ticket types
select fx_event_ticket_type(:'publicTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Public pass'
));
select fx_event_ticket_type(:'privateTicketTypeID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 5
));
select fx_event_ticket_type(:'inactivePublicTicketTypeID', :'eventID', jsonb_build_object(
    'active', false,
    'order', 3,
    'seats_total', 20
));
select fx_event_ticket_type(:'futurePublicTicketTypeID', :'eventID', jsonb_build_object(
    'order', 4,
    'seats_total', 30
));
select fx_event_ticket_type(:'privateOnlyTicketTypeID', :'eventPrivateID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 5
));

-- Current and future prices for public and invitation-only ticket types
select fx_event_ticket_price_window(:'futurePublicWindowID', :'futurePublicTicketTypeID', jsonb_build_object(
    'amount_minor', 2500,
    'starts_at', current_timestamp + interval '1 day'
));
select fx_event_ticket_price_window(:'inactivePublicWindowID', :'inactivePublicTicketTypeID', jsonb_build_object('amount_minor', 2500));
select fx_event_ticket_price_window(:'privateOnlyWindowID', :'privateOnlyTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'privateWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'publicWindowID', :'publicTicketTypeID', jsonb_build_object('amount_minor', 2500));

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
