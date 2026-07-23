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
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    'https://example.test/mobile.png',
    'https://example.test/banner.png',
    :'communityID',
    'Community',
    'Community',
    'https://example.test/logo.png',
    'community'
);

-- Group category owning the test group
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Category');

-- Event category used by deletion fixtures
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Events');

-- Group owning the deletion scenarios
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Group', 'group');

-- Actor deleting the eligible events
insert into "user" (auth_hash, email, user_id, username)
values ('hash', 'actor@example.test', :'actorID', 'actor');

-- Active published event that must be canceled before deletion
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Active',
    :'eventCategoryID',
    :'activeEventID',
    'in-person',
    :'groupID',
    'Active',
    true,
    'active',
    now() + interval '1 day',
    'UTC'
);

-- Canceled event eligible for deletion
insert into event (
    canceled,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    true,
    'Canceled',
    :'eventCategoryID',
    :'canceledEventID',
    'in-person',
    :'groupID',
    'Canceled',
    false,
    'canceled',
    now() + interval '1 day',
    'UTC'
);

-- Unused never-published draft eligible for deletion
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Draft',
    :'eventCategoryID',
    :'draftEventID',
    'in-person',
    :'groupID',
    'Draft',
    false,
    'draft',
    now() + interval '1 day',
    'UTC'
);

-- Canceled event without a requested meeting
insert into event (
    canceled,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    true,
    'No meeting',
    :'eventCategoryID',
    :'eventNoMeetingID',
    'in-person',
    :'groupID',
    null,
    false,
    'No meeting',
    false,
    'no-meeting',
    now() + interval '1 day',
    'UTC'
);

-- Canceled event with requested event and session meetings
insert into event (
    capacity,
    canceled,
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    meeting_in_sync,
    meeting_provider_id,
    meeting_requested,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    100,
    true,
    'Meeting cleanup',
    now() + interval '2 days',
    :'eventCategoryID',
    :'meetingEventID',
    'virtual',
    :'groupID',
    true,
    'zoom',
    true,
    'Meeting cleanup',
    false,
    'meeting-cleanup',
    now() + interval '1 day',
    'UTC'
);

-- Completed past event eligible for deletion without cancellation
insert into event (
    description,
    ends_at,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Past',
    now() - interval '1 hour',
    :'eventCategoryID',
    :'pastEventID',
    'in-person',
    :'groupID',
    'Past',
    true,
    'past',
    now() - interval '2 hours',
    'UTC'
);

-- Active event with unresolved checkout work
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    published,
    slug,
    starts_at,
    timezone
) values (
    'Pending payment',
    :'eventCategoryID',
    :'pendingEventID',
    'in-person',
    :'groupID',
    'Pending payment',
    true,
    'pending-payment',
    now() + interval '1 day',
    'UTC'
);

-- Ticket type owning the unresolved checkout
insert into event_ticket_type (
    event_id,
    event_ticket_type_id,
    "order",
    seats_total,
    title
) values (
    :'pendingEventID',
    :'ticketTypeID',
    1,
    10,
    'General admission'
);

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
    'event not found or inactive',
    'Should reject deletion from the wrong group'
);

-- Should reject replaying deletion for an inactive event
select throws_ok(
    format('select delete_event(%L, %L, %L)', :'actorID', :'groupID', :'draftEventID'),
    'event not found or inactive',
    'Should reject replaying deletion for an inactive event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
