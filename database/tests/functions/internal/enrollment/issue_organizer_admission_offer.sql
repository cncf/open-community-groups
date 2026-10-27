-- Tests issuing pending organizer admission offers with issue-time snapshots.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorUserID '155e0000-0000-0000-0000-000000000001'
\set communityID '155e0000-0000-0000-0000-000000000002'
\set endedEventID '155e0000-0000-0000-0000-000000000003'
\set endedTicketTypeID '155e0000-0000-0000-0000-000000000004'
\set eventCategoryID '155e0000-0000-0000-0000-000000000005'
\set eventID '155e0000-0000-0000-0000-000000000006'
\set freeTicketTypeID '155e0000-0000-0000-0000-000000000007'
\set freeUserID '155e0000-0000-0000-0000-000000000008'
\set groupCategoryID '155e0000-0000-0000-0000-000000000009'
\set groupID '155e0000-0000-0000-0000-000000000010'
\set guardUserID '155e0000-0000-0000-0000-000000000011'
\set paidTicketTypeID '155e0000-0000-0000-0000-000000000012'
\set paidUserID '155e0000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the offer events
select fx_community(:'communityID');

-- Organizer issuing the offers
select fx_user(:'actorUserID');

-- Recipient of the free approval offer
select fx_user(:'freeUserID');

-- Recipient used by the rejected issuance scenarios
select fx_user(:'guardUserID');

-- Recipient of the paid organizer invitation
select fx_user(:'paidUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Group hosting the offer events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Ended event with no claim window left
select fx_event(:'endedEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', current_timestamp - interval '1 hour',
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp - interval '2 hours'
));

-- Event starting within twenty-four hours that collects payments in USD
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'payment_currency_code', 'USD',
    'starts_at', current_timestamp + interval '12 hours'
));

-- Ticket tier of the ended event
select fx_event_ticket_type(:'endedTicketTypeID', :'endedEventID', jsonb_build_object(
    'title', 'Ended admission'
));

-- Free ticket tier snapshotted by the approval offer
select fx_event_ticket_type(:'freeTicketTypeID', :'eventID', jsonb_build_object(
    'title', 'Free admission'
));

-- Paid ticket tier snapshotted by the organizer invitation
select fx_event_ticket_type(:'paidTicketTypeID', :'eventID', jsonb_build_object(
    'order', 2,
    'title', 'Paid admission'
));

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should issue a currency-free pending approval offer for a free tier
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.event_id,
                ao.event_ticket_type_id,
                ao.organizer_user_id,
                ao.source,
                ao.status,
                ao.ticket_title,
                ao.user_id
            from issue_organizer_admission_offer(
                %L::uuid,
                (select e from event e where e.event_id = %L::uuid),
                (select ett from event_ticket_type ett where ett.event_ticket_type_id = %L::uuid),
                %L::uuid,
                0,
                'approval'
            ) ao
        $$,
        :'actorUserID',
        :'eventID',
        :'freeTicketTypeID',
        :'freeUserID'
    ),
    format(
        $$ values (
            0::bigint,
            null::text,
            0::bigint,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'approval'::text,
            'pending'::text,
            'Free admission'::text,
            %L::uuid
        ) $$,
        :'eventID',
        :'freeTicketTypeID',
        :'actorUserID',
        :'freeUserID'
    ),
    'Should issue a currency-free pending approval offer for a free tier'
);

-- Should persist the free approval offer snapshot
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.discount_code,
                ao.event_discount_code_id,
                ao.organizer_user_id,
                ao.source,
                ao.status,
                ao.ticket_title
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'eventID',
        :'freeUserID'
    ),
    format(
        $$ values (
            0::bigint,
            null::text,
            0::bigint,
            null::text,
            null::uuid,
            %L::uuid,
            'approval'::text,
            'pending'::text,
            'Free admission'::text
        ) $$,
        :'actorUserID'
    ),
    'Should persist the free approval offer snapshot'
);

-- Should bound the claim deadline by the start of an event beginning within twenty-four hours
select is(
    (
        select ao.expires_at
        from admission_offer ao
        where ao.event_id = :'eventID'::uuid
        and ao.user_id = :'freeUserID'::uuid
    ),
    current_timestamp + interval '12 hours',
    'Should bound the claim deadline by the start of an event beginning within twenty-four hours'
);

-- Should issue a pending organizer invitation in the event currency for a paid tier
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.event_ticket_type_id,
                ao.organizer_user_id,
                ao.source,
                ao.status,
                ao.ticket_title,
                ao.user_id
            from issue_organizer_admission_offer(
                %L::uuid,
                (select e from event e where e.event_id = %L::uuid),
                (select ett from event_ticket_type ett where ett.event_ticket_type_id = %L::uuid),
                %L::uuid,
                2500,
                'organizer_invitation'
            ) ao
        $$,
        :'actorUserID',
        :'eventID',
        :'paidTicketTypeID',
        :'paidUserID'
    ),
    format(
        $$ values (
            2500::bigint,
            'USD'::text,
            0::bigint,
            %L::uuid,
            %L::uuid,
            'organizer_invitation'::text,
            'pending'::text,
            'Paid admission'::text,
            %L::uuid
        ) $$,
        :'paidTicketTypeID',
        :'actorUserID',
        :'paidUserID'
    ),
    'Should issue a pending organizer invitation in the event currency for a paid tier'
);

-- Should persist the paid organizer invitation snapshot
select results_eq(
    format(
        $$
            select
                ao.amount_minor,
                ao.currency_code,
                ao.discount_amount_minor,
                ao.source,
                ao.status,
                ao.ticket_title
            from admission_offer ao
            where ao.event_id = %L::uuid
            and ao.user_id = %L::uuid
        $$,
        :'eventID',
        :'paidUserID'
    ),
    $$ values (
        2500::bigint,
        'USD'::text,
        0::bigint,
        'organizer_invitation'::text,
        'pending'::text,
        'Paid admission'::text
    ) $$,
    'Should persist the paid organizer invitation snapshot'
);

-- Should reject a missing offer source
select throws_ok(
    format(
        $$
            select issue_organizer_admission_offer(
                %L::uuid,
                (select e from event e where e.event_id = %L::uuid),
                (select ett from event_ticket_type ett where ett.event_ticket_type_id = %L::uuid),
                %L::uuid,
                0,
                null
            )
        $$,
        :'actorUserID',
        :'eventID',
        :'freeTicketTypeID',
        :'guardUserID'
    ),
    'P0001',
    'invalid organizer admission offer source: <NULL>',
    'Should reject a missing offer source'
);

-- Should reject events with no claim window left
select throws_ok(
    format(
        $$
            select issue_organizer_admission_offer(
                %L::uuid,
                (select e from event e where e.event_id = %L::uuid),
                (select ett from event_ticket_type ett where ett.event_ticket_type_id = %L::uuid),
                %L::uuid,
                0,
                'approval'
            )
        $$,
        :'actorUserID',
        :'endedEventID',
        :'endedTicketTypeID',
        :'guardUserID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject events with no claim window left'
);

-- Should reject waitlist offers
select throws_ok(
    format(
        $$
            select issue_organizer_admission_offer(
                %L::uuid,
                (select e from event e where e.event_id = %L::uuid),
                (select ett from event_ticket_type ett where ett.event_ticket_type_id = %L::uuid),
                %L::uuid,
                0,
                'waitlist'
            )
        $$,
        :'actorUserID',
        :'eventID',
        :'freeTicketTypeID',
        :'guardUserID'
    ),
    'P0001',
    'invalid organizer admission offer source: waitlist',
    'Should reject waitlist offers'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
