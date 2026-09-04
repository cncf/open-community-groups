-- Tests guarded event deletion and meeting cleanup behavior.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(22);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set activeEventID 'd1010000-0000-0000-0000-000000000001'
\set actorID 'd1010000-0000-0000-0000-000000000002'
\set canceledEventID 'd1010000-0000-0000-0000-000000000003'
\set communityID 'd1010000-0000-0000-0000-000000000004'
\set draftEventID 'd1010000-0000-0000-0000-000000000005'
\set eventCategoryID 'd1010000-0000-0000-0000-000000000006'
\set eventNoMeetingID 'd1010000-0000-0000-0000-000000000007'
\set groupCategoryID 'd1010000-0000-0000-0000-000000000008'
\set groupID 'd1010000-0000-0000-0000-000000000009'
\set meetingEventID 'd1010000-0000-0000-0000-000000000010'
\set missingGroupID 'd1010000-0000-0000-0000-000000000011'
\set pastEventID 'd1010000-0000-0000-0000-000000000012'
\set pendingEventID 'd1010000-0000-0000-0000-000000000013'
\set pendingPurchaseID 'd1010000-0000-0000-0000-000000000014'
\set requestedSessionID 'd1010000-0000-0000-0000-000000000015'
\set ticketTypeID 'd1010000-0000-0000-0000-000000000016'
\set unrequestedSessionID 'd1010000-0000-0000-0000-000000000017'

-- ============================================================================
-- SEED DATA
-- ============================================================================


-- Community owning the deletion scenarios
select fx_community(:'communityID', jsonb_build_object('name', 'community'));

-- Baseline categories
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category owning the test group
select fx_group_category(:'groupCategoryID', :'communityID', jsonb_build_object('name', 'Category'));

-- Group owning the deletion scenarios
select fx_group(:'groupID', :'communityID', :'groupCategoryID', jsonb_build_object(
    'name', 'Group',
    'slug', 'group'
));

-- Actor deleting the eligible events
select fx_user(:'actorID', jsonb_build_object('username', 'actor-delete-event'));

-- Active published event that must be canceled before deletion
select fx_event(:'activeEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'slug', 'active',
    'starts_at', now() + interval '1 day'
));

-- Canceled event eligible for deletion
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'slug', 'canceled',
    'starts_at', now() + interval '1 day'
));

-- Unused never-published draft eligible for deletion
select fx_event(:'draftEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'slug', 'draft',
    'starts_at', now() + interval '1 day'
));

-- Canceled event without a requested meeting
select fx_event(:'eventNoMeetingID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'meeting_requested', false,
    'starts_at', now() + interval '1 day'
));

-- Canceled event with requested event and session meetings
select fx_event(:'meetingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'capacity', 100,
    'ends_at', now() + interval '2 days',
    'event_kind_id', 'virtual',
    'meeting_in_sync', true,
    'meeting_provider_id', 'zoom',
    'meeting_requested', true,
    'starts_at', now() + interval '1 day'
));

-- Completed past event eligible for deletion without cancellation
select fx_event(:'pastEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'ends_at', now() - interval '1 hour',
    'published', true,
    'slug', 'past',
    'starts_at', now() - interval '2 hours'
));

-- Active event with unresolved checkout work
select fx_event(:'pendingEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'published', true,
    'starts_at', now() + interval '1 day'
));

-- Ticket type owning the unresolved checkout
select fx_event_ticket_type(:'ticketTypeID', :'pendingEventID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));

-- Pending checkout that blocks event deletion
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
    :'pendingEventID',
    :'pendingPurchaseID',
    :'ticketTypeID',
    now() + interval '10 minutes',
    'pending',
    'General admission',
    :'actorID'
);

-- Requested meeting session marked for provider cleanup
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    now() + interval '1 day 30 minutes',
    :'meetingEventID',
    true,
    'zoom',
    true,
    'Requested meeting',
    :'requestedSessionID',
    'virtual',
    now() + interval '1 day'
);

-- Session without a requested meeting that must retain its sync state
insert into session (
    ends_at,
    event_id,
    meeting_in_sync,
    meeting_requested,
    name,
    session_id,
    session_kind_id,
    starts_at
) values (
    now() + interval '1 day 1 hour',
    :'meetingEventID',
    null,
    false,
    'No requested meeting',
    :'unrequestedSessionID',
    'in-person',
    now() + interval '1 day 30 minutes'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should classify deletion eligibility across lifecycle and payment states
select results_eq(
    format($$
        select event_id, get_event_delete_eligibility(%L::uuid, event_id)
        from event
        where group_id = %L::uuid
        order by event_id
    $$, :'groupID', :'groupID'),
    format($$ values
        (%L::uuid, 'cancel-first'::text),
        (%L::uuid, 'allowed'::text),
        (%L::uuid, 'allowed'::text),
        (%L::uuid, 'allowed'::text),
        (%L::uuid, 'allowed'::text),
        (%L::uuid, 'allowed'::text),
        (%L::uuid, 'refunds-pending'::text)
    $$,
        :'activeEventID',
        :'canceledEventID',
        :'draftEventID',
        :'eventNoMeetingID',
        :'meetingEventID',
        :'pastEventID',
        :'pendingEventID'
    ),
    'Should classify deletion eligibility across lifecycle and payment states'
);

-- Should delete an unused never-published draft
select lives_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'draftEventID'),
    'Should delete an unused never-published draft'
);
select is(
    (select deleted from event where event_id = :'draftEventID'),
    true,
    'Should mark the unused draft deleted'
);
select isnt(
    (select deleted_at from event where event_id = :'draftEventID'),
    null,
    'Should timestamp deletion of the unused draft'
);
select is(
    (select published from event where event_id = :'draftEventID'),
    false,
    'Should leave the deleted draft unpublished'
);

-- Should delete a canceled event
select lives_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'canceledEventID'),
    'Should delete a canceled event'
);

-- Should delete a completed past event without cancellation
select lives_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'pastEventID'),
    'Should delete a completed past event without cancellation'
);

-- Should mark requested event and session meetings out of sync
select lives_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'meetingEventID'),
    'Should delete a canceled event with requested meetings'
);
select is(
    (select meeting_in_sync from event where event_id = :'meetingEventID'),
    false,
    'Should mark the requested event meeting out of sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'requestedSessionID'),
    false,
    'Should mark the requested session meeting out of sync'
);
select is(
    (select meeting_in_sync from session where session_id = :'unrequestedSessionID'),
    null,
    'Should preserve the session without a requested meeting'
);

-- Should preserve event meeting sync state when no meeting was requested
select lives_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'eventNoMeetingID'),
    'Should delete a canceled event without a requested meeting'
);
select is(
    (select meeting_in_sync from event where event_id = :'eventNoMeetingID'),
    null,
    'Should preserve event meeting sync state when no meeting was requested'
);

-- Should preserve blocked active events
select throws_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'activeEventID'),
    'OCG01',
    'event must be canceled and all payment work settled before deletion',
    'Should reject an active event that has not been canceled'
);
select is(
    (select deleted from event where event_id = :'activeEventID'),
    false,
    'Should preserve an active event when deletion is blocked'
);

-- Should preserve events with unresolved payment work
select throws_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'pendingEventID'),
    'OCG01',
    'event must be canceled and all payment work settled before deletion',
    'Should reject an event with unresolved payment work'
);
select is(
    (select deleted from event where event_id = :'pendingEventID'),
    false,
    'Should preserve an event with unresolved payment work'
);

-- Should record one audit row for every successful deletion
select is(
    (select count(*)::int from audit_log where action = 'event_deleted'),
    5,
    'Should record one audit row for every successful deletion'
);
select ok(
    exists (
        select 1
        from audit_log
        where action = 'event_deleted'
        and actor_user_id = :'actorID'
        and community_id = :'communityID'
        and event_id = :'meetingEventID'
        and group_id = :'groupID'
        and resource_id = :'meetingEventID'
        and resource_type = 'event'
    ),
    'Should record the expected deletion audit ownership'
);

-- Should retain soft-deleted event rows
select is(
    (select count(*)::int from event where event_id = :'draftEventID'),
    1,
    'Should retain soft-deleted event rows'
);

-- Should reject deletion from the wrong group
select throws_ok(
    format(
        'select delete_event(%L, %L, %L)',
        :'actorID', :'missingGroupID', :'activeEventID'
    ),
    'OCG01',
    'event not found or inactive',
    'Should reject deletion from the wrong group'
);

-- Should reject replaying deletion for an inactive event
select throws_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'draftEventID'),
    'OCG01',
    'event not found or inactive',
    'Should reject replaying deletion for an inactive event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
