-- Tests confirming event purchase attendees.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set canceledByUserID 'f3090000-0000-0000-0000-000000000001'
\set canceledUserID 'f3090000-0000-0000-0000-000000000002'
\set communityID 'f3090000-0000-0000-0000-000000000003'
\set confirmedUserID 'f3090000-0000-0000-0000-000000000004'
\set eventCategoryID 'f3090000-0000-0000-0000-000000000005'
\set eventID 'f3090000-0000-0000-0000-000000000006'
\set groupCategoryID 'f3090000-0000-0000-0000-000000000007'
\set groupID 'f3090000-0000-0000-0000-000000000008'
\set insertedUserID 'f3090000-0000-0000-0000-000000000009'
\set invitationCanceledUserID 'f3090000-0000-0000-0000-00000000000a'
\set invitationPendingUserID 'f3090000-0000-0000-0000-00000000000b'
\set registrationPendingUserID 'f3090000-0000-0000-0000-00000000000c'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline community, categories, group, event and users
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_event_category(:'eventCategoryID', :'communityID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');
select fx_event(:'eventID', :'groupID', :'eventCategoryID');
select fx_user(:'canceledByUserID');
select fx_user(:'canceledUserID');
select fx_user(:'confirmedUserID');
select fx_user(:'insertedUserID');
select fx_user(:'invitationCanceledUserID');
select fx_user(:'invitationPendingUserID');
select fx_user(:'registrationPendingUserID');

-- Attendee rows covering checkout-compatible and incompatible states
insert into event_attendee (
    event_id,
    user_id,
    attendance_canceled_at,
    attendance_canceled_by_user_id,
    manually_invited,
    status
) values (
    :'eventID',
    :'canceledUserID',
    current_timestamp - interval '1 hour',
    :'canceledByUserID',
    false,
    'attendance-canceled'
), (
    :'eventID',
    :'confirmedUserID',
    null,
    null,
    false,
    'confirmed'
), (
    :'eventID',
    :'invitationCanceledUserID',
    null,
    null,
    true,
    'invitation-canceled'
), (
    :'eventID',
    :'invitationPendingUserID',
    null,
    null,
    true,
    'invitation-pending'
), (
    :'eventID',
    :'registrationPendingUserID',
    null,
    null,
    false,
    'registration-questions-pending'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should confirm existing confirmed attendance
select is(
    confirm_event_purchase_attendee(:'eventID', :'confirmedUserID', false),
    true,
    'Should confirm existing confirmed attendance'
);

-- Should insert confirmed attendance when none exists
select is(
    confirm_event_purchase_attendee(:'eventID', :'insertedUserID', true),
    true,
    'Should insert confirmed attendance when none exists'
);

-- Should reject invitation-pending attendance
select is(
    confirm_event_purchase_attendee(:'eventID', :'invitationPendingUserID', false),
    false,
    'Should reject invitation-pending attendance'
);

-- Should revive attendance-canceled attendance
select is(
    confirm_event_purchase_attendee(:'eventID', :'canceledUserID', true),
    true,
    'Should revive attendance-canceled attendance'
);

-- Should revive invitation-canceled attendance
select is(
    confirm_event_purchase_attendee(:'eventID', :'invitationCanceledUserID', false),
    true,
    'Should revive invitation-canceled attendance'
);

-- Should revive registration-questions-pending attendance
select is(
    confirm_event_purchase_attendee(:'eventID', :'registrationPendingUserID', false),
    true,
    'Should revive registration-questions-pending attendance'
);

-- Should persist attendee confirmation states
select results_eq(
    format(
        $$
            select
                ea.user_id,
                ea.attendance_canceled_at is null,
                ea.attendance_canceled_by_user_id is null,
                ea.manually_invited,
                ea.status
            from event_attendee ea
            where ea.event_id = %L::uuid
            and ea.user_id in (%L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid, %L::uuid)
            order by ea.user_id
        $$,
        :'eventID',
        :'canceledUserID',
        :'confirmedUserID',
        :'insertedUserID',
        :'invitationCanceledUserID',
        :'invitationPendingUserID',
        :'registrationPendingUserID'
    ),
    format(
        $$ values
            (%L::uuid, true, true, true, 'confirmed'::text),
            (%L::uuid, true, true, false, 'confirmed'::text),
            (%L::uuid, true, true, true, 'confirmed'::text),
            (%L::uuid, true, true, false, 'confirmed'::text),
            (%L::uuid, true, true, true, 'invitation-pending'::text),
            (%L::uuid, true, true, false, 'confirmed'::text)
        $$,
        :'canceledUserID',
        :'confirmedUserID',
        :'insertedUserID',
        :'invitationCanceledUserID',
        :'invitationPendingUserID',
        :'registrationPendingUserID'
    ),
    'Should persist attendee confirmation states'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
