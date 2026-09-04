-- Tests resolving admission offer capacity conflicts.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set allocatedPurchaseID 'f30c0000-0000-0000-0000-000000000001'
\set allocatedUserID 'f30c0000-0000-0000-0000-000000000002'
\set communityID 'f30c0000-0000-0000-0000-000000000003'
\set eventCategoryID 'f30c0000-0000-0000-0000-000000000004'
\set eventID 'f30c0000-0000-0000-0000-000000000005'
\set fullTicketTypeID 'f30c0000-0000-0000-0000-000000000006'
\set groupCategoryID 'f30c0000-0000-0000-0000-000000000007'
\set groupID 'f30c0000-0000-0000-0000-000000000008'
\set notFullTicketTypeID 'f30c0000-0000-0000-0000-000000000009'
\set nullEventID 'f30c0000-0000-0000-0000-00000000000a'
\set nullTicketTypeID 'f30c0000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event, ticket types and user
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'fullTicketTypeID', :'eventID', jsonb_build_object('seats_total', 1));
select fx_event_ticket_type(:'notFullTicketTypeID', :'eventID', jsonb_build_object(
    'order', 2,
    'seats_total', 1
));
select fx_user(:'allocatedUserID');

-- Completed purchase that fills one ticket tier
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventID',
    :'allocatedPurchaseID',
    :'fullTicketTypeID',
    'completed',
    'Allocated admission',
    :'allocatedUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should ignore capacity when seats are unlimited
select is(
    admission_offer_capacity_conflict(
        jsonb_populate_record(null::event_ticket_type, jsonb_build_object(
            'event_id', :'nullEventID'::uuid,
            'event_ticket_type_id', :'nullTicketTypeID'::uuid,
            'seats_total', null
        )),
        array[]::uuid[]
    ),
    null::text,
    'Should ignore capacity when seats are unlimited'
);

-- Should report queue priority when promoted users filled the tier
select is(
    (select admission_offer_capacity_conflict(ett, array[:'allocatedUserID'::uuid]) from event_ticket_type ett where ett.event_ticket_type_id = :'fullTicketTypeID'),
    'queue-has-priority',
    'Should report queue priority when promoted users filled the tier'
);

-- Should report sold out when no queued users were promoted
select is(
    (select admission_offer_capacity_conflict(ett, array[]::uuid[]) from event_ticket_type ett where ett.event_ticket_type_id = :'fullTicketTypeID'),
    'ticket-type-sold-out',
    'Should report sold out when no queued users were promoted'
);

-- Should return null while seats remain
select is(
    (select admission_offer_capacity_conflict(ett, array[]::uuid[]) from event_ticket_type ett where ett.event_ticket_type_id = :'notFullTicketTypeID'),
    null::text,
    'Should return null while seats remain'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
