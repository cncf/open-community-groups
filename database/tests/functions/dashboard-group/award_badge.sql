-- Tests atomic explicit-recipient badge awards and notification enqueueing.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(42);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set actorID 'b1080000-0000-0000-0000-000000000001'
\set attendeeID 'b1080000-0000-0000-0000-000000000002'
\set badgeID 'b1080000-0000-0000-0000-000000000003'
\set canceledEventID 'b1080000-0000-0000-0000-000000000004'
\set checkedInID 'b1080000-0000-0000-0000-000000000005'
\set communityID 'b1080000-0000-0000-0000-000000000006'
\set emptyEventID 'b1080000-0000-0000-0000-000000000007'
\set eventCategoryID 'b1080000-0000-0000-0000-000000000008'
\set eventHostID 'b1080000-0000-0000-0000-000000000009'
\set eventID 'b1080000-0000-0000-0000-000000000010'
\set eventOrganizerID 'b1080000-0000-0000-0000-000000000011'
\set eventSpeakerID 'b1080000-0000-0000-0000-000000000012'
\set groupCategoryID 'b1080000-0000-0000-0000-000000000013'
\set groupID 'b1080000-0000-0000-0000-000000000014'
\set groupMemberID 'b1080000-0000-0000-0000-000000000015'
\set outsiderID 'b1080000-0000-0000-0000-000000000016'
\set sessionID 'b1080000-0000-0000-0000-000000000017'
\set sessionSpeakerID 'b1080000-0000-0000-0000-000000000018'
\set unverifiedID 'b1080000-0000-0000-0000-000000000019'
\set unknownBadgeID 'b1080000-0000-0000-0000-000000000020'
\set viewerID 'b1080000-0000-0000-0000-000000000021'
\set lifecycleJobID 'b1080000-0000-0000-0000-000000000022'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Verified users representing every supported and unsupported award role
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values
    ('hash', 'award-admin@example.test', true, 'Award Admin', :'actorID', 'award-admin'),
    ('hash', 'award-attendee@example.test', true, 'Award Attendee', :'attendeeID', 'award-attendee'),
    ('hash', 'award-checked-in@example.test', true, 'Award Checked In', :'checkedInID', 'award-checked-in'),
    ('hash', 'award-host@example.test', true, 'Award Host', :'eventHostID', 'award-host'),
    ('hash', 'award-organizer@example.test', true, 'Award Organizer', :'eventOrganizerID', 'award-organizer'),
    ('hash', 'award-speaker@example.test', true, 'Award Speaker', :'eventSpeakerID', 'award-speaker'),
    ('hash', 'award-member@example.test', true, 'Award Member', :'groupMemberID', 'award-member'),
    ('hash', 'award-outsider@example.test', true, 'Award Outsider', :'outsiderID', 'award-outsider'),
    ('hash', 'award-session-speaker@example.test', true, 'Award Session Speaker', :'sessionSpeakerID', 'award-session-speaker'),
    ('hash', 'award-viewer@example.test', true, 'Award Viewer', :'viewerID', 'award-viewer');

-- Unverified checked-in attendee excluded from every award scope
insert into "user" (auth_hash, email, email_verified, name, user_id, username)
values ('hash', 'award-unverified@example.test', false, 'Award Unverified', :'unverifiedID', 'award-unverified');

-- Community containing the issuing group
insert into community (
    banner_mobile_url,
    banner_url,
    community_id,
    description,
    display_name,
    logo_url,
    name
) values (
    '/mobile',
    '/banner',
    :'communityID',
    'Description',
    'Award Community',
    '/logo',
    'award-community'
);

-- Event category used by award fixtures
insert into event_category (community_id, event_category_id, name)
values (:'communityID', :'eventCategoryID', 'Conference');

-- Group category used by the issuer
insert into group_category (community_id, group_category_id, name)
values (:'communityID', :'groupCategoryID', 'Technology');

-- Group issuing the badge
insert into "group" (community_id, group_category_id, group_id, name, slug)
values (:'communityID', :'groupCategoryID', :'groupID', 'Award Group', 'award-group');

-- Badge manager, accepted team recipient, pending recipient, and unauthorized viewer roles
insert into group_team (accepted, group_id, role, user_id)
values
    (true, :'groupID', 'events-manager', :'actorID'),
    (true, :'groupID', 'viewer', :'eventOrganizerID'),
    (false, :'groupID', 'viewer', :'outsiderID'),
    (true, :'groupID', 'viewer', :'viewerID');

-- Active event providing the recipient context
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Description',
    :'eventCategoryID',
    :'eventID',
    'in-person',
    :'groupID',
    'Award Event',
    'award-event',
    'UTC'
);

-- Canceled event rejected by award validation
insert into event (
    canceled,
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    true,
    'Description',
    :'eventCategoryID',
    :'canceledEventID',
    'in-person',
    :'groupID',
    'Canceled Award Event',
    'canceled-award-event',
    'UTC'
);

-- Active event with no eligible recipients
insert into event (
    description,
    event_category_id,
    event_id,
    event_kind_id,
    group_id,
    name,
    slug,
    timezone
) values (
    'Description',
    :'eventCategoryID',
    :'emptyEventID',
    'in-person',
    :'groupID',
    'Empty Award Event',
    'empty-award-event',
    'UTC'
);

-- Confirmed attendees covering registered, checked-in, and unverified states
insert into event_attendee (checked_in, event_id, status, user_id)
values
    (false, :'eventID', 'confirmed', :'attendeeID'),
    (true, :'eventID', 'confirmed', :'checkedInID'),
    (true, :'eventID', 'confirmed', :'unverifiedID');

-- Host eligible for a single award
insert into event_host (event_id, user_id)
values (:'eventID', :'eventHostID');

-- Organizer intentionally ineligible for a single award
insert into event_organizer (event_id, "order", user_id)
values (:'eventID', 1, :'eventOrganizerID');

-- Event speaker eligible for a single award
insert into event_speaker (event_id, featured, user_id)
values (:'eventID', false, :'eventSpeakerID');

-- Session containing an eligible session speaker
insert into session (event_id, name, session_id, session_kind_id, starts_at)
values (:'eventID', 'Award Session', :'sessionID', 'hybrid', '2026-01-01 10:00:00+00');

-- Session speaker eligible for a single award
insert into session_speaker (featured, session_id, user_id)
values (false, :'sessionID', :'sessionSpeakerID');

-- Group member intentionally ineligible without an event
insert into group_member (group_id, user_id)
values (:'groupID', :'groupMemberID');

-- Definition used for immutable award snapshots
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Check in', 'Attended Award Event', :'groupID', 'attendee.png', 'Attendee');

-- Test helper that drains every currently due one-batch award job
create function test_process_badge_award_jobs()
returns void as $$
declare
    v_job jsonb;
begin
    loop
        v_job := claim_badge_award_job();
        exit when v_job is null;

        perform process_badge_award_job_batch(
            (v_job->>'badge_award_job_id')::uuid,
            (v_job->>'claim_id')::uuid,
            25,
            1000000
        );
    end loop;
end;
$$ language plpgsql;

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should award an explicit attendee list
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'checkedInID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should award an explicit attendee list'
);
select test_process_badge_award_jobs();

-- Should award multiple recipients and skip active holders
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'attendeeID'::uuid, :'checkedInID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":1}'::jsonb,
    'Should award multiple recipients and skip active holders'
);
select test_process_badge_award_jobs();

-- Should award an event host
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventHostID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should award an event host'
);

-- Should avoid amplifying durable work when the same recipient is already queued
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventHostID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":0,"skipped_count":1}'::jsonb,
    'Should skip a recipient already owned by durable award work'
);
select test_process_badge_award_jobs();

-- Should reject an event organizer
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'eventOrganizerID', :'eventID'
    ),
    'badge recipient is not eligible',
    'Should reject an event organizer'
);

-- Should award an event speaker
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventSpeakerID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should award an event speaker'
);
select test_process_badge_award_jobs();

-- Should award a session speaker
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'sessionSpeakerID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should award a session speaker'
);
select test_process_badge_award_jobs();

-- Should skip an active single attendee
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'attendeeID'::uuid, :'attendeeID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":0,"skipped_count":1}'::jsonb,
    'Should deduplicate recipients before skipping an active attendee'
);

-- Should award an accepted group team member without an event
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventOrganizerID'::uuid],
        null
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should award an accepted group team member without an event'
);
select test_process_badge_award_jobs();

-- Should require at least one recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{}'::uuid[], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'eventID'
    ),
    'badge recipients cannot be empty',
    'Should require at least one recipient'
);

-- Should reject a mixed list atomically when one recipient is ineligible
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid, %L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'attendeeID', :'outsiderID', :'eventID'
    ),
    'badge recipient is not eligible',
    'Should reject a mixed list atomically when one recipient is ineligible'
);

-- Should retain no outsider award after atomic validation fails
select is(
    (
        select count(*)::integer
        from user_badge
        where user_id = :'outsiderID'
    ),
    0,
    'Should retain no outsider award after atomic validation fails'
);

-- Should reject a null recipient array
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, null, %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'emptyEventID'
    ),
    'badge recipients cannot be empty',
    'Should reject a null recipient array'
);

-- Should reject a canceled event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'attendeeID', :'canceledEventID'
    ),
    'event not found',
    'Should reject a canceled event'
);

-- Should reject an unknown badge definition
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'unknownBadgeID', :'attendeeID', :'eventID'
    ),
    'badge not found',
    'Should reject an unknown badge definition'
);

-- Should reject an unknown group boundary
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', gen_random_uuid(), :'badgeID', :'attendeeID', :'eventID'
    ),
    'group not found',
    'Should reject an unknown group boundary'
);

-- Should reject an unknown recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[gen_random_uuid()], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'eventID'
    ),
    'badge recipient is not eligible',
    'Should reject an unknown recipient'
);

-- Should reject an unverified recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'unverifiedID', :'eventID'
    ),
    'badge recipient is not eligible',
    'Should reject an unverified recipient'
);

-- Should reject a recipient outside the event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'outsiderID', :'eventID'
    ),
    'badge recipient is not eligible',
    'Should reject a recipient outside the event'
);

-- Should reject a group member without an event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], null)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'groupMemberID'
    ),
    'badge recipient is not eligible',
    'Should reject a non-team group member without an event'
);

-- Should reject a pending group team member without an event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], null)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'outsiderID'
    ),
    'badge recipient is not eligible',
    'Should reject a pending group team member without an event'
);

-- Should reject a viewer before mutation
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'viewerID', :'communityID', :'groupID', :'badgeID', :'attendeeID', :'eventID'
    ),
    '42501',
    'badge permission denied',
    'Should reject a viewer before mutation'
);

-- Should build an opaque snapshot without recipient identity data
select ok(
    (
        select snapshot @> '{"criteria":"Check in","description":"Attended Award Event","image_file_name":"attendee.png","name":"Attendee"}'::jsonb
            and snapshot::text not ilike '%recipient%'
            and snapshot::text not ilike '%email%'
        from user_badge
        where user_id = :'attendeeID'
    ),
    'Should build an opaque snapshot without recipient identity data'
);

-- Should allocate an in-range unique status index
select ok(
    (
        select status_list_index between 0 and 131071
        from user_badge
        where user_id = :'attendeeID'
    ),
    'Should allocate an in-range unique status index'
);

-- Should enqueue one notification for an awarded attendee
select is(
    (select count(*)::integer from notification where kind = 'badge-awarded' and user_id = :'attendeeID'),
    1,
    'Should enqueue one notification for an awarded attendee'
);

-- Should write issuance audit history after insertion
select is(
    (select count(*)::integer from audit_log where action = 'badge_awarded' and actor_user_id = :'actorID'),
    6,
    'Should write issuance audit history after insertion'
);

-- Should not enqueue a notification for a skipped active holder
select is(
    (select count(*)::integer from notification where kind = 'badge-awarded' and user_id = :'attendeeID'),
    1,
    'Should not enqueue a notification for a skipped active holder'
);

-- Should reuse the group status list while it has capacity
select is(
    (select count(*)::integer from badge_status_list where group_id = :'groupID'),
    1,
    'Should reuse the group status list while it has capacity'
);

-- Should revoke the first credential before a re-award
select lives_ok(
    format(
        $$select revoke_group_user_badge(%L::uuid, %L::uuid, %L::uuid, (select user_badge_id from user_badge where badge_id = %L::uuid and user_id = %L::uuid and revoked_at is null), 're-award test')$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'attendeeID'
    ),
    'Should revoke the first credential before a re-award'
);

-- Should allow a new credential after permanent revocation
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'attendeeID'::uuid],
        :'eventID'
    )::jsonb,
    '{"awarded_count":1,"skipped_count":0}'::jsonb,
    'Should allow a new credential after permanent revocation'
);
select test_process_badge_award_jobs();

-- Should retain revoked history after a re-award
select is(
    (select count(*)::integer from user_badge where badge_id = :'badgeID' and user_id = :'attendeeID'),
    2,
    'Should retain revoked history after a re-award'
);

-- Should retain successful queue summaries without recipient rows
select is(
    (
        select count(*)::integer
        from badge_award_job
        where status = 'completed'
        and not exists (
            select 1
            from badge_award_job_recipient bajr
            where bajr.badge_award_job_id = badge_award_job.badge_award_job_id
        )
    ),
    7,
    'Should retain completed durable award summaries'
);

-- Queue one synthetic job for failure, operator retry, and recovery lifecycle tests
insert into badge_award_job (
    badge_award_job_id,
    accepted_count,
    actor_username,
    badge_snapshot,
    community_id,
    group_id,
    recipient_count,

    actor_user_id,
    badge_id,
    event_id
) values (
    :'lifecycleJobID',
    1,
    'award-admin',
    '{"criteria":"Check in","description":"Attended Award Event","image_file_name":"attendee.png","issuer":{"community_id":"b1080000-0000-0000-0000-000000000006","community_name":"Award Community","group_id":"b1080000-0000-0000-0000-000000000014","group_name":"Award Group"},"name":"Attendee"}',
    :'communityID',
    :'groupID',
    1,

    :'actorID',
    :'badgeID',
    :'eventID'
);

insert into badge_award_job_recipient (badge_award_job_id, position, user_id)
values (:'lifecycleJobID', 0, :'attendeeID');

-- Should claim the oldest due job with a durable ownership token
select is(
    (claim_badge_award_job()->>'badge_award_job_id')::uuid,
    :'lifecycleJobID'::uuid,
    'Should claim the oldest due badge award job'
);

-- Should terminally fail work that exhausts its bounded retry budget
select is(
    record_badge_award_job_failure(
        :'lifecycleJobID',
        (select claim_id from badge_award_job where badge_award_job_id = :'lifecycleJobID'),
        'synthetic failure',
        1
    ),
    true,
    'Should terminally fail a badge award job after its retry budget'
);

select ok(
    (
        select status = 'failed'
            and completed_at is not null
            and error = 'synthetic failure'
            and failure_count = 1
        from badge_award_job
        where badge_award_job_id = :'lifecycleJobID'
    ),
    'Should retain terminal badge award failure details'
);

-- Should allow an operator-reviewed failed job to be retried
select lives_ok(
    format($$select requeue_badge_award_job(%L::uuid)$$, :'lifecycleJobID'),
    'Should requeue one operator-reviewed failed badge award job'
);

select ok(
    (
        select status = 'pending'
            and completed_at is null
            and error is null
            and failure_count = 0
        from badge_award_job
        where badge_award_job_id = :'lifecycleJobID'
    ),
    'Should reset retry state when requeueing a failed badge award job'
);

-- Should recover a claim abandoned longer than the processing timeout
select claim_badge_award_job();
update badge_award_job
set claimed_at = current_timestamp - interval '1 hour'
where badge_award_job_id = :'lifecycleJobID';

select is(
    recover_stale_badge_award_jobs(60, 10),
    1,
    'Should recover an abandoned badge award claim'
);

select ok(
    (
        select status = 'pending'
            and claim_id is null
            and failure_count = 1
            and error = 'badge award worker claim expired'
        from badge_award_job
        where badge_award_job_id = :'lifecycleJobID'
    ),
    'Should release recovered work with a durable failure count'
);

-- Should release a claim without consuming failure budget when the global rate is exhausted
select claim_badge_award_job();
select is(
    (
        process_badge_award_job_batch(
            :'lifecycleJobID',
            (select claim_id from badge_award_job where badge_award_job_id = :'lifecycleJobID'),
            25,
            1
        )->>'rate_limited'
    )::boolean,
    true,
    'Should pause badge issuance at the global rolling rate limit'
);

-- Should remove only successful summaries beyond their retention period
update badge_award_job
set completed_at = current_timestamp - interval '60 days'
where status = 'completed';

select is(
    cleanup_badge_award_jobs(2592000),
    7,
    'Should clean completed badge award summaries after retention'
);

select is(
    (select count(*)::integer from badge_award_job where status = 'completed'),
    0,
    'Should leave no expired completed badge award summaries'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
