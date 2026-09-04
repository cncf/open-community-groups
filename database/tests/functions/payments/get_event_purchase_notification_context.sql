-- Tests loading purchase identifiers used to compose notifications.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(2);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendeeID 'e07f0000-0000-0000-0000-000000000001'
\set communityID 'e07f0000-0000-0000-0000-000000000002'
\set eventCategoryID 'e07f0000-0000-0000-0000-000000000003'
\set eventID 'e07f0000-0000-0000-0000-000000000004'
\set eventTicketTypeID 'e07f0000-0000-0000-0000-000000000005'
\set groupCategoryID 'e07f0000-0000-0000-0000-000000000006'
\set groupID 'e07f0000-0000-0000-0000-000000000007'
\set otherGroupID 'e07f0000-0000-0000-0000-000000000008'
\set purchaseID 'e07f0000-0000-0000-0000-000000000009'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, users and group
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_user(:'attendeeID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Published event used by the notification-context scenario
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Ticket type required by the purchase row
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 50,
    'title', 'General admission'
));

-- Purchase whose identifiers are returned to the notification composer
insert into event_purchase (
    amount_minor,
    charge_model,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    platform_fee_bps,
    provisional_platform_fee_amount_minor,
    status,
    ticket_title,
    user_id
) values (
    0,
    'ocg-free',
    null,
    :'eventID',
    :'purchaseID',
    :'eventTicketTypeID',
    0,
    0,
    'pending',
    'General admission',
    :'attendeeID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return the community and event for a group-owned purchase
select is(
    get_event_purchase_notification_context(
        :'groupID'::uuid,
        :'purchaseID'::uuid
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid
    ),
    'Should return the community and event for a group-owned purchase'
);

-- Should return null when the purchase belongs to another group
select is(
    get_event_purchase_notification_context(
        :'otherGroupID'::uuid,
        :'purchaseID'::uuid
    ),
    null,
    'Should return null when the purchase belongs to another group'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
