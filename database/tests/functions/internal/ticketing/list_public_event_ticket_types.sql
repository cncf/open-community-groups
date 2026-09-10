-- Tests listing normalized public event ticket types.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c020000-0000-0000-0000-000000000001'
\set eventCategoryID '0c020000-0000-0000-0000-000000000002'
\set eventID '0c020000-0000-0000-0000-000000000003'
\set eventPrivateID '0c020000-0000-0000-0000-000000000004'
\set groupCategoryID '0c020000-0000-0000-0000-000000000005'
\set groupID '0c020000-0000-0000-0000-000000000006'
\set mixedPrivateTicketTypeID '0c020000-0000-0000-0000-00000000000b'
\set privateTicketTypeID '0c020000-0000-0000-0000-000000000007'
\set privateWindowID '0c020000-0000-0000-0000-000000000008'
\set publicTicketTypeID '0c020000-0000-0000-0000-000000000009'
\set publicWindowID '0c020000-0000-0000-0000-00000000000a'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Events with mixed and fully private ticket inventories
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));
select fx_event(:'eventPrivateID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'payment_currency_code', 'USD'
));

-- Public and invitation-only ticket types
select fx_event_ticket_type(:'privateTicketTypeID', :'eventPrivateID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 5
));
select fx_event_ticket_type(:'publicTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'Public pass'
));

-- Current prices for public and invitation-only ticket types
select fx_event_ticket_price_window(:'privateWindowID', :'privateTicketTypeID', jsonb_build_object('amount_minor', 5000));
select fx_event_ticket_price_window(:'publicWindowID', :'publicTicketTypeID', jsonb_build_object('amount_minor', 2500));

-- Invitation-only ticket on the mixed event
select fx_event_ticket_type(:'mixedPrivateTicketTypeID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'order', 2,
    'seats_total', 3
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude invitation-only ticket types from mixed events
select is(
    list_public_event_ticket_types(:'eventID'::uuid),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'availability', 'public',
            'current_price', jsonb_build_object('amount_minor', 2500),
            'event_ticket_type_id', :'publicTicketTypeID'::uuid,
            'order', 1,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 2500,
                    'event_ticket_price_window_id', :'publicWindowID'::uuid
                )
            ),
            'remaining_seats', 10,
            'seats_total', 10,
            'sold_out', false,
            'title', 'Public pass'
        )
    ),
    'Should exclude invitation-only ticket types from mixed events'
);

-- Should return null for fully invitation-only events
select ok(
    list_public_event_ticket_types(:'eventPrivateID'::uuid) is null,
    'Should return null for fully invitation-only events'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
