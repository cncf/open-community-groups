-- Tests upgrading schema-68 enrollment data to required ticket tiers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(20);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '69000000-0000-0000-0000-000000000001'
\set limitedEventID '69000000-0000-0000-0000-000000000010'
\set pastEventID '69000000-0000-0000-0000-000000000011'
\set overbookedEventID '69000000-0000-0000-0000-000000000012'
\set unlimitedEventID '69000000-0000-0000-0000-000000000013'
\set ticketedEventID '69000000-0000-0000-0000-000000000014'
\set privateEventID '69000000-0000-0000-0000-000000000015'
\set publicTicketTypeID '69000000-0000-0000-0000-000000000020'
\set privateTicketTypeID '69000000-0000-0000-0000-000000000022'
\set confirmedUserID '69000000-0000-0000-0000-000000000030'
\set pendingUserID '69000000-0000-0000-0000-000000000031'
\set pastPendingUserID '69000000-0000-0000-0000-000000000032'
\set waitlistUserID '69000000-0000-0000-0000-000000000035'
\set requestUserID '69000000-0000-0000-0000-000000000036'
\set privateRequestUserID '69000000-0000-0000-0000-000000000038'
\set activeOfferID '69000000-0000-0000-0000-000000000040'
\set terminalOfferID '69000000-0000-0000-0000-000000000041'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should remove the obsolete schema-68 admission function.
select hasnt_function(
    'complete_non_ticketed_event_admission_offer',
    array['uuid', 'uuid', 'uuid', 'jsonb', 'uuid']::name[],
    'the obsolete schema-68 admission function is removed'
);

-- Should give every event a ticket tier.
select is(
    (select count(*)::int from event e where not exists (
        select 1 from event_ticket_type ett where ett.event_id = e.event_id
    )),
    0,
    'every event has a ticket tier after migration'
);

-- Should expand limited capacity only enough to preserve occupied users.
select is(
    (select capacity from event where event_id = :'limitedEventID'),
    2,
    'limited capacity expands to preserve distinct occupied users'
);

-- Should give a formerly unlimited past event the default tier size.
select is(
    (select capacity from event where event_id = :'pastEventID'),
    500,
    'a formerly unlimited past event receives the default tier size'
);

-- Should expand an overbooked event enough to preserve confirmed users.
select is(
    (select capacity from event where event_id = :'overbookedEventID'),
    2,
    'an overbooked event receives enough tier seats for confirmed users'
);

-- Should give a formerly unlimited future event the default tier size.
select is(
    (select capacity from event where event_id = :'unlimitedEventID'),
    500,
    'a formerly unlimited future event receives the default tier size'
);

-- Should synthesize one free completed purchase for a confirmed attendee.
select is(
    (
        select count(*)::int
        from event_purchase
        where event_id = :'limitedEventID'
        and user_id = :'confirmedUserID'
        and status = 'completed'
        and amount_minor = 0
    ),
    1,
    'a confirmed attendee receives one free completed purchase'
);

-- Should synthesize purchases for every confirmed overbooked attendee.
select is(
    (
        select count(*)::int
        from event_purchase
        where event_id = :'overbookedEventID'
        and status = 'completed'
    ),
    2,
    'all confirmed attendees on an overbooked event receive purchases'
);

-- Should remove a pending-question attendee that already has an active offer.
select is(
    (
        select count(*)::int
        from event_attendee
        where event_id = :'limitedEventID'
        and user_id = :'pendingUserID'
    ),
    0,
    'a pending-question attendee is removed when an active offer already exists'
);

-- Should reuse an existing active offer without a uniqueness collision.
select is(
    (
        select count(*)::int
        from admission_offer
        where event_id = :'limitedEventID'
        and user_id = :'pendingUserID'
        and status in ('checkout_pending', 'pending')
    ),
    1,
    'migration reuses an existing active offer without a uniqueness collision'
);

-- Should bound an active legacy organizer offer's runtime deadline.
select ok(
    (
        select expires_at > current_timestamp
            and expires_at <= least(current_timestamp + interval '24 hours', e.starts_at)
        from admission_offer ao
        join event e using (event_id)
        where ao.admission_offer_id = :'activeOfferID'
    ),
    'an active legacy organizer offer receives a bounded runtime deadline'
);

-- Should convert a stale past pending attendee to a terminal offer.
select is(
    (
        select status
        from admission_offer
        where event_id = :'pastEventID'
        and user_id = :'pastPendingUserID'
    ),
    'expired',
    'a stale past pending attendee becomes a terminal offer'
);

-- Should give the past pending attendee a valid historical deadline.
select ok(
    (
        select expires_at > created_at and expires_at <= current_timestamp
        from admission_offer
        where event_id = :'pastEventID'
        and user_id = :'pastPendingUserID'
    ),
    'the past pending attendee receives a valid historical deadline'
);

-- Should map a terminal nullable-tier legacy offer with a valid deadline.
select ok(
    (
        select expires_at > created_at
            and event_ticket_type_id = :'publicTicketTypeID'
        from admission_offer
        where admission_offer_id = :'terminalOfferID'
    ),
    'a terminal nullable-tier legacy offer is mapped with a valid deadline'
);

-- Should map a nullable multi-tier waitlist row to the public tier.
select is(
    (
        select event_ticket_type_id
        from event_waitlist
        where event_id = :'ticketedEventID'
        and user_id = :'waitlistUserID'
    ),
    :'publicTicketTypeID'::uuid,
    'a nullable waitlist row on a multi-tier event maps to the public tier'
);

-- Should map a nullable multi-tier public request to the public tier.
select is(
    (
        select event_ticket_type_id
        from event_invitation_request
        where event_id = :'ticketedEventID'
        and user_id = :'requestUserID'
    ),
    :'publicTicketTypeID'::uuid,
    'a nullable public request on a multi-tier event maps to the public tier'
);

-- Should preserve a generic fully private request for organizer assignment.
select ok(
    (
        select event_ticket_type_id is null
        from event_invitation_request
        where event_id = :'privateEventID'
        and user_id = :'privateRequestUserID'
    ),
    'a generic fully private request remains unassigned for organizer review'
);

-- Should synchronize every event capacity to its authoritative tier sum.
select is(
    (
        select count(*)::int
        from event e
        where e.capacity <> (
            select sum(ett.seats_total)::int
            from event_ticket_type ett
            where ett.event_id = e.event_id
        )
    ),
    0,
    'event capacity matches the authoritative tier sum'
);

-- Should leave no migrated ticket tier oversubscribed.
select is(
    (
        select count(*)::int
        from event_ticket_type ett
        where get_event_ticket_type_allocated_seat_count(
            ett.event_id,
            ett.event_ticket_type_id
        ) > ett.seats_total
    ),
    0,
    'no migrated ticket tier is oversubscribed'
);

-- Should let a migrated attendee leave through the synthesized purchase.
select is(
    leave_event(:'communityID', :'limitedEventID', :'confirmedUserID')::jsonb,
    '{"left_status": "attendee"}'::jsonb,
    'a migrated confirmed attendee can leave through its synthesized purchase'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
