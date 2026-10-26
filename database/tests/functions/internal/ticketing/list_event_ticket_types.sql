-- Tests listing normalized event ticket types.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '0c120000-0000-0000-0000-000000000001'
\set eventCategoryID '0c120000-0000-0000-0000-000000000002'
\set eventID '0c120000-0000-0000-0000-000000000003'
\set eventNoTicketTypesID '0c120000-0000-0000-0000-000000000004'
\set groupCategoryID '0c120000-0000-0000-0000-000000000005'
\set groupID '0c120000-0000-0000-0000-000000000006'
\set ticketTypeAlphaID '0c120000-0000-0000-0000-000000000007'
\set ticketTypeBetaID '0c120000-0000-0000-0000-000000000014'
\set ticketTypeWorkshopID '0c120000-0000-0000-0000-000000000008'
\set ticketTypeZetaID '0c120000-0000-0000-0000-000000000013'
\set user1ID '0c120000-0000-0000-0000-000000000009'
\set user2ID '0c120000-0000-0000-0000-00000000000a'
\set user3ID '0c120000-0000-0000-0000-00000000000b'
\set windowAlphaCurrentID '0c120000-0000-0000-0000-00000000000f'
\set windowAlphaExpiredID '0c120000-0000-0000-0000-000000000010'
\set windowAlphaFutureID '0c120000-0000-0000-0000-000000000011'
\set windowWorkshopID '0c120000-0000-0000-0000-000000000012'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories, event categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Users
select fx_user(:'user1ID', jsonb_build_object('username', 'user1'));
select fx_user(:'user2ID', jsonb_build_object('username', 'user2'));
select fx_user(:'user3ID', jsonb_build_object('username', 'user3'));

-- Events
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));
select fx_event(:'eventNoTicketTypesID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'event_kind_id', 'virtual',
    'published', true
));

-- Ticket type listed after Workshop despite its lower id and earlier title
select fx_event_ticket_type(:'ticketTypeAlphaID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 5,
    'title', 'Alpha pass'
));

-- Sold-out ticket type sharing order 3 with Zeta, listed first by title despite its higher id
select fx_event_ticket_type(:'ticketTypeBetaID', :'eventID', jsonb_build_object(
    'order', 3,
    'seats_total', 1,
    'title', 'Beta pass'
));

-- Ticket type listed first by order despite its higher id and later title
select fx_event_ticket_type(:'ticketTypeWorkshopID', :'eventID', jsonb_build_object(
    'availability', 'invitation_only',
    'description', 'Workshop access',
    'order', 1,
    'seats_total', 5,
    'title', 'Workshop pass'
));

-- Ticket type sharing order 3 with Beta, listed last by title despite its lower id
select fx_event_ticket_type(:'ticketTypeZetaID', :'eventID', jsonb_build_object(
    'order', 3,
    'seats_total', 5,
    'title', 'Zeta pass'
));

-- Event ticket price windows
select fx_event_ticket_price_window(:'windowAlphaExpiredID', :'ticketTypeAlphaID', jsonb_build_object(
    'amount_minor', 3000,
    'ends_at', current_timestamp - interval '2 days'
));
select fx_event_ticket_price_window(:'windowAlphaCurrentID', :'ticketTypeAlphaID', jsonb_build_object(
    'amount_minor', 2500,
    'ends_at', current_timestamp + interval '1 day',
    'starts_at', current_timestamp - interval '1 day'
));
select fx_event_ticket_price_window(:'windowAlphaFutureID', :'ticketTypeAlphaID', jsonb_build_object(
    'amount_minor', 3500,
    'starts_at', current_timestamp + interval '2 days'
));
select fx_event_ticket_price_window(:'windowWorkshopID', :'ticketTypeWorkshopID', jsonb_build_object('amount_minor', 1500));

-- Alpha purchases: one completed seat and one lapsed pending hold that frees its seat
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventID',
    :'ticketTypeAlphaID',
    null,
    'completed',
    'Alpha pass',
    :'user1ID'
), (
    0,
    'USD',
    :'eventID',
    :'ticketTypeAlphaID',
    current_timestamp - interval '1 hour',
    'pending',
    'Alpha pass',
    :'user2ID'
);

-- Beta purchase that allocates its only seat
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventID',
    :'ticketTypeBetaID',
    'completed',
    'Beta pass',
    :'user3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should list ticket types with normalized prices and inventory
select is(
    list_event_ticket_types(:'eventID'::uuid),
    jsonb_build_array(
        jsonb_build_object(
            'active', true,
            'availability', 'invitation_only',
            'current_price', jsonb_build_object(
                'amount_minor', 1500
            ),
            'description', 'Workshop access',
            'event_ticket_type_id', :'ticketTypeWorkshopID'::uuid,
            'order', 1,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 1500,
                    'event_ticket_price_window_id', :'windowWorkshopID'::uuid
                )
            ),
            'remaining_seats', 5,
            'seats_total', 5,
            'sold_out', false,
            'title', 'Workshop pass'
        ),
        jsonb_build_object(
            'active', true,
            'availability', 'public',
            'current_price', jsonb_build_object(
                'amount_minor', 2500,
                'ends_at', current_timestamp + interval '1 day',
                'starts_at', current_timestamp - interval '1 day'
            ),
            'event_ticket_type_id', :'ticketTypeAlphaID'::uuid,
            'order', 2,
            'price_windows', jsonb_build_array(
                jsonb_build_object(
                    'amount_minor', 3000,
                    'ends_at', current_timestamp - interval '2 days',
                    'event_ticket_price_window_id', :'windowAlphaExpiredID'::uuid
                ),
                jsonb_build_object(
                    'amount_minor', 2500,
                    'ends_at', current_timestamp + interval '1 day',
                    'event_ticket_price_window_id', :'windowAlphaCurrentID'::uuid,
                    'starts_at', current_timestamp - interval '1 day'
                ),
                jsonb_build_object(
                    'amount_minor', 3500,
                    'event_ticket_price_window_id', :'windowAlphaFutureID'::uuid,
                    'starts_at', current_timestamp + interval '2 days'
                )
            ),
            'remaining_seats', 4,
            'seats_total', 5,
            'sold_out', false,
            'title', 'Alpha pass'
        ),
        jsonb_build_object(
            'active', true,
            'availability', 'public',
            'event_ticket_type_id', :'ticketTypeBetaID'::uuid,
            'order', 3,
            'price_windows', '[]'::jsonb,
            'remaining_seats', 0,
            'seats_total', 1,
            'sold_out', true,
            'title', 'Beta pass'
        ),
        jsonb_build_object(
            'active', true,
            'availability', 'public',
            'event_ticket_type_id', :'ticketTypeZetaID'::uuid,
            'order', 3,
            'price_windows', '[]'::jsonb,
            'remaining_seats', 5,
            'seats_total', 5,
            'sold_out', false,
            'title', 'Zeta pass'
        )
    ),
    'Should list ticket types with normalized prices and inventory'
);

-- Should return null for events without ticket types
select ok(
    list_event_ticket_types(:'eventNoTicketTypesID'::uuid) is null,
    'Should return null for events without ticket types'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
