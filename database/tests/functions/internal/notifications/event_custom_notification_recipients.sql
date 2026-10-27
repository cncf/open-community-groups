-- Tests organizer event email recipient eligibility.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(15);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set attendanceCanceledUserID '9e0a0000-0000-0000-0000-000000000001'
\set communityID '9e0a0000-0000-0000-0000-000000000002'
\set confirmedUserID '9e0a0000-0000-0000-0000-000000000003'
\set eventCategoryID '9e0a0000-0000-0000-0000-000000000004'
\set eventID '9e0a0000-0000-0000-0000-000000000005'
\set expiredHoldPurchaseID '9e0a0000-0000-0000-0000-000000000006'
\set expiredHoldUserID '9e0a0000-0000-0000-0000-000000000007'
\set groupCategoryID '9e0a0000-0000-0000-0000-000000000008'
\set groupID '9e0a0000-0000-0000-0000-000000000009'
\set invitationCanceledUserID '9e0a0000-0000-0000-0000-000000000010'
\set invitationPendingUserID '9e0a0000-0000-0000-0000-000000000011'
\set invitationRejectedUserID '9e0a0000-0000-0000-0000-000000000012'
\set liveHoldPurchaseID '9e0a0000-0000-0000-0000-000000000013'
\set liveHoldUserID '9e0a0000-0000-0000-0000-000000000014'
\set optedOutUserID '9e0a0000-0000-0000-0000-000000000015'
\set otherGroupEventID '9e0a0000-0000-0000-0000-000000000016'
\set otherGroupID '9e0a0000-0000-0000-0000-000000000017'
\set otherGroupUserID '9e0a0000-0000-0000-0000-000000000018'
\set ownerMutedUserID '9e0a0000-0000-0000-0000-000000000019'
\set questionsPendingUserID '9e0a0000-0000-0000-0000-000000000020'
\set ticketTypeID '9e0a0000-0000-0000-0000-000000000021'
\set unrelatedMutedUserID '9e0a0000-0000-0000-0000-000000000022'
\set unverifiedUserID '9e0a0000-0000-0000-0000-000000000023'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community owning the groups under test
select fx_community(:'communityID');

-- User with canceled attendance
select fx_user(:'attendanceCanceledUserID');

-- User with confirmed attendance
select fx_user(:'confirmedUserID');

-- User whose pending checkout hold has lapsed
select fx_user(:'expiredHoldUserID');

-- User with a canceled invitation
select fx_user(:'invitationCanceledUserID');

-- User with a pending invitation
select fx_user(:'invitationPendingUserID');

-- User who rejected an invitation
select fx_user(:'invitationRejectedUserID');

-- User holding a live pending checkout
select fx_user(:'liveHoldUserID');

-- User opted out of organizer messages
select fx_user(:'optedOutUserID');

-- User attending an event of another group
select fx_user(:'otherGroupUserID');

-- User who muted the event's group
select fx_user(:'ownerMutedUserID');

-- User with pending registration questions
select fx_user(:'questionsPendingUserID');

-- User who muted an unrelated group
select fx_user(:'unrelatedMutedUserID');

-- User without a verified email
select fx_user(:'unverifiedUserID', jsonb_build_object('email_verified', false));

-- Event category for every event under test
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category for every group under test
select fx_group_category(:'groupCategoryID', :'communityID');

-- Organizer messages opt-out
insert into user_notification_opt_out (notification_category_id, user_id)
values ('organizer-messages', :'optedOutUserID');

-- Group owning the event under test
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Unrelated group owning another event
select fx_group(:'otherGroupID', :'communityID', :'groupCategoryID');

-- Event under test
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Event owned by the unrelated group
select fx_event(:'otherGroupEventID', :'otherGroupID', :'eventCategoryID', jsonb_build_object('published', true));

-- Owner group mute
insert into user_group_notification_mute (group_id, user_id)
values (:'groupID', :'ownerMutedUserID');

-- Unrelated group mute
insert into user_group_notification_mute (group_id, user_id)
values (:'otherGroupID', :'unrelatedMutedUserID');

-- Canceled attendance
insert into event_attendee (attendance_canceled_at, event_id, status, user_id)
values (current_timestamp, :'eventID', 'attendance-canceled', :'attendanceCanceledUserID');

-- Confirmed attendance
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'confirmedUserID');

-- Registration questions pending behind a lapsed checkout hold
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'registration-questions-pending', :'expiredHoldUserID');

-- Canceled invitation
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'invitation-canceled', :'invitationCanceledUserID');

-- Pending invitation
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'invitation-pending', :'invitationPendingUserID');

-- Rejected invitation
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'invitation-rejected', :'invitationRejectedUserID');

-- Registration questions pending behind a live checkout hold
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'registration-questions-pending', :'liveHoldUserID');

-- Confirmed attendance of a user opted out of organizer messages
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'optedOutUserID');

-- Confirmed attendance at the unrelated group's event
insert into event_attendee (event_id, status, user_id)
values (:'otherGroupEventID', 'confirmed', :'otherGroupUserID');

-- Confirmed attendance of a user who muted the event's group
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'ownerMutedUserID');

-- Pending registration questions without a checkout
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'registration-questions-pending', :'questionsPendingUserID');

-- Confirmed attendance of a user who muted an unrelated group
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'unrelatedMutedUserID');

-- Confirmed attendance of a user without a verified email
insert into event_attendee (event_id, status, user_id)
values (:'eventID', 'confirmed', :'unverifiedUserID');

-- Ticket type used by pending checkout purchases
select fx_event_ticket_type(:'ticketTypeID', :'eventID', jsonb_build_object(
    'seats_total', 100,
    'title', 'General admission'
));

-- Pending checkout whose hold has lapsed
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'expiredHoldPurchaseID',
    0,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    current_timestamp - interval '10 minutes',
    'pending',
    'General admission',
    :'expiredHoldUserID'
);

-- Pending checkout whose hold is still live
insert into event_purchase (
    event_purchase_id,
    amount_minor,
    currency_code,
    discount_amount_minor,
    event_id,
    event_ticket_type_id,
    hold_expires_at,
    status,
    ticket_title,
    user_id
) values (
    :'liveHoldPurchaseID',
    0,
    'USD',
    0,
    :'eventID',
    :'ticketTypeID',
    current_timestamp + interval '10 minutes',
    'pending',
    'General admission',
    :'liveHoldUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should exclude attendees opted out of organizer messages
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'optedOutUserID'::uuid
    ),
    'Should exclude attendees opted out of organizer messages'
);

-- Should exclude attendees who muted the event's group
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'ownerMutedUserID'::uuid
    ),
    'Should exclude attendees who muted the event''s group'
);

-- Should exclude attendees with a live pending checkout hold
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'liveHoldUserID'::uuid
    ),
    'Should exclude attendees with a live pending checkout hold'
);

-- Should exclude attendees without a verified email
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'unverifiedUserID'::uuid
    ),
    'Should exclude attendees without a verified email'
);

-- Should exclude canceled attendance
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'attendanceCanceledUserID'::uuid
    ),
    'Should exclude canceled attendance'
);

-- Should exclude canceled invitations
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'invitationCanceledUserID'::uuid
    ),
    'Should exclude canceled invitations'
);

-- Should exclude pending invitations
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'invitationPendingUserID'::uuid
    ),
    'Should exclude pending invitations'
);

-- Should exclude rejected invitations
select ok(
    not exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'invitationRejectedUserID'::uuid
    ),
    'Should exclude rejected invitations'
);

-- Should include attendees muting an unrelated group
select ok(
    exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'unrelatedMutedUserID'::uuid
    ),
    'Should include attendees muting an unrelated group'
);

-- Should include attendees whose pending checkout hold has lapsed
select ok(
    exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'expiredHoldUserID'::uuid
    ),
    'Should include attendees whose pending checkout hold has lapsed'
);

-- Should include attendees with pending registration questions
select ok(
    exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'questionsPendingUserID'::uuid
    ),
    'Should include attendees with pending registration questions'
);

-- Should include confirmed attendees
select ok(
    exists (
        select 1
        from event_custom_notification_recipients(:'groupID'::uuid, :'eventID'::uuid) r
        where r.user_id = :'confirmedUserID'::uuid
    ),
    'Should include confirmed attendees'
);

-- Should return every eligible attendee exactly once
select results_eq(
    format($$
        select r.user_id
        from event_custom_notification_recipients(%L::uuid, %L::uuid) r
        order by r.user_id
    $$, :'groupID', :'eventID'),
    format($$
        values (%L::uuid), (%L::uuid), (%L::uuid), (%L::uuid)
    $$, :'confirmedUserID', :'expiredHoldUserID', :'questionsPendingUserID', :'unrelatedMutedUserID'),
    'Should return every eligible attendee exactly once'
);

-- Should return no recipients for an event of another group
select is_empty(
    format($$
        select r.user_id
        from event_custom_notification_recipients(%L::uuid, %L::uuid) r
    $$, :'groupID', :'otherGroupEventID'),
    'Should return no recipients for an event of another group'
);

-- Should return the attendees of the owning group's event
select results_eq(
    format($$
        select r.user_id
        from event_custom_notification_recipients(%L::uuid, %L::uuid) r
    $$, :'otherGroupID', :'otherGroupEventID'),
    format($$ values (%L::uuid) $$, :'otherGroupUserID'),
    'Should return the attendees of the owning group''s event'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
