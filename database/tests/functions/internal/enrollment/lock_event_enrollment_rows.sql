-- Tests locking event enrollment rows.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID 'f3040000-0000-0000-0000-000000000001'
\set eventCategoryID 'f3040000-0000-0000-0000-000000000002'
\set eventID 'f3040000-0000-0000-0000-000000000003'
\set extraUserID 'f3040000-0000-0000-0000-000000000004'
\set groupCategoryID 'f3040000-0000-0000-0000-000000000005'
\set groupID 'f3040000-0000-0000-0000-000000000006'
\set offerID 'f3040000-0000-0000-0000-000000000007'
\set offerUserID 'f3040000-0000-0000-0000-000000000008'
\set otherEventID 'f3040000-0000-0000-0000-000000000009'
\set otherTicketTypeID 'f3040000-0000-0000-0000-00000000000a'
\set purchaseID 'f3040000-0000-0000-0000-00000000000b'
\set purchaseUserID 'f3040000-0000-0000-0000-00000000000c'
\set ticketTypeID 'f3040000-0000-0000-0000-00000000000d'
\set waitlistUserID 'f3040000-0000-0000-0000-00000000000e'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, events, ticket types and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID');
select fx_event_ticket_type(:'ticketTypeID', :'eventID');
select fx_event_ticket_type(:'otherTicketTypeID', :'otherEventID');
select fx_user(:'extraUserID');
select fx_user(:'offerUserID');
select fx_user(:'purchaseUserID');
select fx_user(:'waitlistUserID');

-- Active offer locked with the event enrollment rows
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'offerID',
    current_timestamp - interval '1 hour',
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'approval',
    'pending',
    :'offerUserID'
);

-- Pending purchase locked with the event enrollment rows
insert into event_purchase (
    amount_minor,
    currency_code,
    event_id,
    event_purchase_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    0,
    'USD',
    :'eventID',
    :'purchaseID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'pending',
    'Lock admission',
    :'purchaseUserID'
);

-- Waitlist row included in scoped ticket-tier locks
insert into event_waitlist (event_id, event_ticket_type_id, user_id)
values (:'eventID', :'ticketTypeID', :'waitlistUserID');

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep locked rows available to the current transaction
select lives_ok(
    format(
        $$
            select lock_event_enrollment_rows(%L::uuid, %L::uuid, %L::uuid);
            select 1 from admission_offer where admission_offer_id = %L::uuid for update nowait;
            select 1 from event_purchase where event_purchase_id = %L::uuid for update nowait;
        $$,
        :'eventID',
        :'ticketTypeID',
        :'extraUserID',
        :'offerID',
        :'purchaseID'
    ),
    'Should keep locked rows available to the current transaction'
);

-- Should leave enrollment rows unchanged
select results_eq(
    format(
        $$
            select
                (select count(*) from admission_offer where event_id = %L::uuid),
                (select count(*) from event_purchase where event_id = %L::uuid),
                (select count(*) from event_waitlist where event_id = %L::uuid)
        $$,
        :'eventID',
        :'eventID',
        :'eventID'
    ),
    $$ values (1::bigint, 1::bigint, 1::bigint) $$,
    'Should leave enrollment rows unchanged'
);

-- Should lock an existing scoped ticket tier
select lives_ok(
    format($$select lock_event_enrollment_rows(%L::uuid, %L::uuid, null)$$, :'eventID', :'ticketTypeID'),
    'Should lock an existing scoped ticket tier'
);

-- Should lock rows without a scoped ticket tier or user
select lives_ok(
    format($$select lock_event_enrollment_rows(%L::uuid, null, null)$$, :'eventID'),
    'Should lock rows without a scoped ticket tier or user'
);

-- Should reject a scoped ticket tier owned by another event
select throws_ok(
    format($$select lock_event_enrollment_rows(%L::uuid, %L::uuid, null)$$, :'eventID', :'otherTicketTypeID'),
    'ticket type not found',
    'Should reject a scoped ticket tier owned by another event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
