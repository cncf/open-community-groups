-- Tests unpublishing events and closing their enrollment state.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledEventID '3a360000-0000-0000-0000-000000000017'
\set canceledEventTicketTypeID '3a360000-0000-0000-0000-000000000018'
\set cohostGroupID '3a360000-0000-0000-0000-000000000016'
\set communityID '3a360000-0000-0000-0000-000000000001'
\set eventCategoryID '3a360000-0000-0000-0000-000000000002'
\set eventID '3a360000-0000-0000-0000-000000000003'
\set eventTicketTypeID '3a360000-0000-0000-0000-000000000014'
\set groupCategoryID '3a360000-0000-0000-0000-000000000005'
\set groupID '3a360000-0000-0000-0000-000000000006'
\set missingGroupID '3a360000-0000-0000-0000-000000000007'
\set offerID '3a360000-0000-0000-0000-000000000011'
\set offerUserID '3a360000-0000-0000-0000-000000000012'
\set sessionMeetingID '3a360000-0000-0000-0000-000000000008'
\set userID '3a360000-0000-0000-0000-000000000010'
\set waitlistUserID '3a360000-0000-0000-0000-000000000013'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the unpublish scenarios
select fx_community(:'communityID');

-- User holding the active organizer offer
select fx_user(:'offerUserID');

-- User who published the events and issued the organizer offer
select fx_user(:'userID', jsonb_build_object('username', 'user-unpublish-event'));

-- User queued on the event waitlist
select fx_user(:'waitlistUserID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category
select fx_group_category(:'groupCategoryID', :'communityID');

-- Co-host group that approved its invitation
select fx_group(:'cohostGroupID', :'communityID', :'groupCategoryID');

-- Group owning the events
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Canceled published event that can still be unpublished
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'ends_at', '2025-06-03 11:00:00+00',
    'published', true,
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', '2025-06-03 10:00:00+00'
));

-- Event (published, with meeting_in_sync=true to verify it gets set to false)
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 100,
    'ends_at', '2025-06-01 11:00:00+00',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'published', true,
    'published_at', now(),
    'published_by', :'userID',
    'starts_at', '2025-06-01 10:00:00+00',
    'waitlist_enabled', true
));

-- Approved co-host invitation preserved through unpublish
insert into event_cohost (approved_at, event_cohost_status_id, event_id, group_id)
values ('2025-01-01 00:00:00+00', 'approved', :'eventID', :'cohostGroupID');

-- Ticket type satisfying the enrollment invariant of the canceled event
select fx_event_ticket_type(:'canceledEventTicketTypeID', :'canceledEventID', jsonb_build_object(
    'seats_total', 100
));

-- Ticket type satisfying the enrollment invariant of the meeting event
select fx_event_ticket_type(:'eventTicketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100
));

-- Session with meeting_requested=true (should be marked as out of sync)
insert into session (
    session_id,
    event_id,
    name,
    starts_at,
    ends_at,
    session_kind_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested
) values (
    :'sessionMeetingID',
    :'eventID',
    'Session With Meeting',
    '2025-06-01 10:00:00+00',
    '2025-06-01 10:30:00+00',
    'virtual',
    true,
    'zoom',
    true
);

-- Active organizer offer canceled when the event is unpublished
insert into admission_offer (
    admission_offer_id,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'offerID',
    :'eventID',
    :'eventTicketTypeID',
    current_timestamp + interval '1 hour',
    :'userID',
    'organizer_invitation',
    'pending',
    :'offerUserID'
);

-- Event-level FIFO queue cleared when the event is unpublished
insert into event_waitlist (
    event_id,
    event_ticket_type_id,
    user_id
) values (
    :'eventID',
    :'eventTicketTypeID',
    :'waitlistUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should clear published flags and metadata
select lives_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventID'
    ),
    'Should clear published flags and metadata'
);

-- Should set published=false
select is(
    (select published from event where event_id = :'eventID'),
    false,
    'Should set published=false'
);

-- Should set published_at to null
select is(
    (select published_at from event where event_id = :'eventID'),
    null,
    'Should set published_at to null'
);

-- Should set published_by to null
select is(
    (select published_by from event where event_id = :'eventID'),
    null,
    'Should set published_by to null'
);

-- Should create the expected audit row
select results_eq(
    $$
        select
            action,
            actor_user_id,
            actor_username,
            community_id,
            group_id,
            event_id,
            resource_type,
            resource_id
        from audit_log
        where action = 'event_unpublished'
    $$,
    format(
        $$
        values (
            'event_unpublished',
            null::uuid,
            null::text,
            %L::uuid,
            %L::uuid,
            %L::uuid,
            'event',
            %L::uuid
        )
        $$,
        :'communityID',
        :'groupID',
        :'eventID',
        :'eventID'
    ),
    'Should create the expected audit row'
);

-- Should allow replaying an already unpublished event
select lives_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'eventID'
    ),
    'Should allow replaying an already unpublished event'
);

-- Should not duplicate the unpublish audit row on replay
select is(
    (
        select count(*)::int
        from audit_log
        where action = 'event_unpublished'
        and event_id = :'eventID'::uuid
    ),
    1,
    'Should not duplicate the unpublish audit row on replay'
);

-- Should cancel active offers and clear queues when unpublishing
select results_eq(
    format(
        $$
            select
                (
                    select status
                    from admission_offer
                    where admission_offer_id = %L::uuid
                ),
                (
                    select count(*)
                    from event_waitlist
                    where event_id = %L::uuid
                )
        $$,
        :'offerID',
        :'eventID'
    ),
    $$ values ('canceled'::text, 0::bigint) $$,
    'Should cancel active offers and clear queues when unpublishing'
);

-- Should preserve co-host status and approval evidence
select results_eq(
    format(
        $$select event_cohost_status_id, approved_at from event_cohost where event_id = %L::uuid$$,
        :'eventID'
    ),
    $$values ('approved', '2025-01-01 00:00:00+00'::timestamptz)$$,
    'Should preserve co-host status and approval evidence'
);

-- Should mark the requested event meeting out of sync
select is(
    (select meeting_in_sync from event where event_id = :'eventID'),
    false,
    'Should mark the requested event meeting out of sync'
);

-- Should mark the requested session meeting out of sync
select is(
    (select meeting_in_sync from session where session_id = :'sessionMeetingID'),
    false,
    'Should mark the requested session meeting out of sync'
);

-- Should unpublish a canceled event
select lives_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'groupID',
        :'canceledEventID'
    ),
    'Should unpublish a canceled event'
);
select results_eq(
    format(
        $$select canceled, published, published_at, published_by from event where event_id = %L::uuid$$,
        :'canceledEventID'
    ),
    $$values (true, false, null::timestamptz, null::uuid)$$,
    'Should clear the publication state of the canceled event'
);

-- Should throw error when group_id does not match
select throws_ok(
    format(
        'select unpublish_event(null::uuid, %L::uuid, %L::uuid)',
        :'missingGroupID',
        :'eventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should throw error when group_id does not match'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
