-- Tests explicit-recipient badge awards and notification enqueueing.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(37);

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
\set multiOrganizer1ID 'b1080000-0000-0000-0000-000000000021'
\set multiOrganizer2ID 'b1080000-0000-0000-0000-000000000022'
\set otherEventID 'b1080000-0000-0000-0000-000000000023'
\set otherEventOrganizerID 'b1080000-0000-0000-0000-000000000024'
\set outsideOrganizerID 'b1080000-0000-0000-0000-000000000025'
\set outsiderID 'b1080000-0000-0000-0000-000000000016'
\set proposalAuthorID 'b1080000-0000-0000-0000-000000000030'
\set proposalCoSpeakerID 'b1080000-0000-0000-0000-000000000031'
\set proposalID 'b1080000-0000-0000-0000-000000000032'
\set proposalSessionID 'b1080000-0000-0000-0000-000000000033'
\set proposalSubmissionID 'b1080000-0000-0000-0000-000000000034'
\set removedOrganizerEventID 'b1080000-0000-0000-0000-000000000026'
\set removedOrganizerID 'b1080000-0000-0000-0000-000000000027'
\set sessionID 'b1080000-0000-0000-0000-000000000017'
\set sessionSpeakerID 'b1080000-0000-0000-0000-000000000018'
\set teamMemberID 'b1080000-0000-0000-0000-000000000028'
\set unknownBadgeID 'b1080000-0000-0000-0000-000000000020'
\set unverifiedID 'b1080000-0000-0000-0000-000000000019'
\set unverifiedOrganizerID 'b1080000-0000-0000-0000-000000000029'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community containing the issuing group
select fx_community(:'communityID', jsonb_build_object('description', 'Description'));

-- Badge manager awarding the badges
select fx_user(:'actorID', jsonb_build_object('username', 'actor-award-badge'));

-- Confirmed attendee who has not checked in
select fx_user(:'attendeeID');

-- Confirmed attendee who checked in
select fx_user(:'checkedInID');

-- Host of the award event
select fx_user(:'eventHostID');

-- Organizer of the award event on the group team
select fx_user(:'eventOrganizerID');

-- Event-level speaker of the award event
select fx_user(:'eventSpeakerID');

-- Group member without an event role or team membership
select fx_user(:'groupMemberID');

-- First organizer awarded together with another organizer
select fx_user(:'multiOrganizer1ID');

-- Second organizer awarded together with another organizer
select fx_user(:'multiOrganizer2ID');

-- Organizer of another event only
select fx_user(:'otherEventOrganizerID');

-- Organizer of the award event outside the group team
select fx_user(:'outsideOrganizerID');

-- Pending group team member
select fx_user(:'outsiderID');

-- Author of the CFS proposal linked to an award event session
select fx_user(:'proposalAuthorID');

-- Co-speaker of the CFS proposal linked to an award event session
select fx_user(:'proposalCoSpeakerID');

-- Organizer removed from their event before the award
select fx_user(:'removedOrganizerID');

-- Speaker assigned to an award event session
select fx_user(:'sessionSpeakerID');

-- Accepted group team member who does not organize the award event
select fx_user(:'teamMemberID');

-- Unverified checked-in attendee excluded from every award scope
select fx_user(:'unverifiedID', jsonb_build_object('email_verified', false));

-- Unverified event organizer excluded from event awards
select fx_user(:'unverifiedOrganizerID', jsonb_build_object('email_verified', false));

-- Event category used by the award events
select fx_event_category(:'eventCategoryID', :'communityID');

-- Group category used by the issuing group
select fx_group_category(:'groupCategoryID', :'communityID');

-- CFS proposal whose author and co-speaker speak at the linked session
insert into session_proposal (
    session_proposal_id,
    description,
    duration,
    session_proposal_level_id,
    title,
    user_id,
    co_speaker_user_id
) values (
    :'proposalID',
    'Proposal description',
    interval '30 minutes',
    'beginner',
    'Proposal',
    :'proposalAuthorID',
    :'proposalCoSpeakerID'
);

-- Group issuing the badges
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Definition used for immutable award snapshots
insert into badge (badge_id, criteria, description, group_id, image_file_name, name)
values (:'badgeID', 'Check in', 'Attended Award Event', :'groupID', 'attendee.png', 'Attendee');

-- Active event providing the recipient context
select fx_event(:'eventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'description', 'Description',
    'name', 'Award Event'
));

-- Canceled event rejected by award validation
select fx_event(:'canceledEventID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'canceled', true,
    'description', 'Description'
));

-- Active event with no eligible recipients
select fx_event(:'emptyEventID', :'groupID', :'eventCategoryID', jsonb_build_object('description', 'Description'));

-- Active event whose organizer is not an organizer of the award event
select fx_event(:'otherEventID', :'groupID', :'eventCategoryID', jsonb_build_object('description', 'Description'));

-- Active event whose organizer is removed before the award
select fx_event(:'removedOrganizerEventID', :'groupID', :'eventCategoryID', jsonb_build_object('description', 'Description'));

-- Group member intentionally ineligible without an event
insert into group_member (group_id, user_id)
values (:'groupID', :'groupMemberID');

-- Badge manager, accepted team recipients, and pending recipient roles
insert into group_team (accepted, group_id, role, user_id)
values
    (true, :'groupID', 'events-manager', :'actorID'),
    (true, :'groupID', 'viewer', :'eventOrganizerID'),
    (false, :'groupID', 'viewer', :'outsiderID'),
    (true, :'groupID', 'viewer', :'teamMemberID');

-- Approved submission of the CFS proposal to the award event
insert into cfs_submission (cfs_submission_id, event_id, session_proposal_id, status_id)
values (:'proposalSubmissionID', :'eventID', :'proposalID', 'approved');

-- Confirmed attendees covering registered, checked-in, and unverified states
insert into event_attendee (checked_in, event_id, status, user_id)
values
    (false, :'eventID', 'confirmed', :'attendeeID'),
    (true, :'eventID', 'confirmed', :'checkedInID'),
    (true, :'eventID', 'confirmed', :'unverifiedID');

-- Host eligible for a single award
insert into event_host (event_id, user_id)
values (:'eventID', :'eventHostID');

-- Organizers of the award event, including users outside the group team
insert into event_organizer (event_id, "order", user_id)
values
    (:'eventID', 1, :'eventOrganizerID'),
    (:'eventID', 2, :'outsideOrganizerID'),
    (:'eventID', 3, :'multiOrganizer1ID'),
    (:'eventID', 4, :'multiOrganizer2ID'),
    (:'eventID', 5, :'unverifiedOrganizerID');

-- Organizer of another event only
insert into event_organizer (event_id, "order", user_id)
values (:'otherEventID', 1, :'otherEventOrganizerID');

-- Organizer removed from the event before the award
insert into event_organizer (event_id, "order", user_id)
values (:'removedOrganizerEventID', 1, :'removedOrganizerID');

-- Event speaker eligible for a single award
insert into event_speaker (event_id, featured, user_id)
values (:'eventID', false, :'eventSpeakerID');

-- Session containing an eligible session speaker
insert into session (event_id, name, session_id, session_kind_id, starts_at)
values (:'eventID', 'Award Session', :'sessionID', 'hybrid', '2026-01-01 10:00:00+00');

-- Session linked to the CFS proposal, without assigned speakers
insert into session (cfs_submission_id, event_id, name, session_id, session_kind_id, starts_at)
values (:'proposalSubmissionID', :'eventID', 'Proposal Session', :'proposalSessionID', 'hybrid', '2026-01-01 11:00:00+00');

-- Session speaker eligible for a single award
insert into session_speaker (featured, session_id, user_id)
values (false, :'sessionID', :'sessionSpeakerID');

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
    '{"queued_count":1,"skipped_count":0}'::jsonb,
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
    '{"queued_count":1,"skipped_count":1}'::jsonb,
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
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should award an event host'
);

-- Should skip a recipient already owned by durable award work
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventHostID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":0,"skipped_count":1}'::jsonb,
    'Should skip a recipient already owned by durable award work'
);
select test_process_badge_award_jobs();

-- Should award an event organizer
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'eventOrganizerID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should award an event organizer'
);
select test_process_badge_award_jobs();

-- Should award an event organizer outside the group team
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'outsideOrganizerID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should award an event organizer outside the group team'
);

-- Should link the organizer award job to the event
select is(
    (
        select baj.event_id
        from badge_award_job baj
        join badge_award_job_recipient bajr using (badge_award_job_id)
        where bajr.user_id = :'outsideOrganizerID'::uuid
    ),
    :'eventID'::uuid,
    'Should link the organizer award job to the event'
);
select test_process_badge_award_jobs();

-- Should award multiple organizers in one request
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'multiOrganizer1ID'::uuid, :'multiOrganizer2ID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":2,"skipped_count":0}'::jsonb,
    'Should award multiple organizers in one request'
);
select test_process_badge_award_jobs();

-- Should reject an organizer of another event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'otherEventOrganizerID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject an organizer of another event'
);

-- Should remove the organizer before the award
select lives_ok(
    format(
        $$select sync_event_organizers(%L::uuid, '[]'::jsonb)$$,
        :'removedOrganizerEventID'
    ),
    'Should remove the organizer before the award'
);

-- Should reject a removed organizer without another role
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'removedOrganizerID', :'removedOrganizerEventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a removed organizer without another role'
);

-- Should reject a team member who is not an event organizer for an event award
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'teamMemberID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a team member who is not an event organizer for an event award'
);

-- Should reject an unverified organizer
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'unverifiedOrganizerID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject an unverified organizer'
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
    '{"queued_count":1,"skipped_count":0}'::jsonb,
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
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should award a session speaker'
);
select test_process_badge_award_jobs();

-- Should award the CFS proposal speakers of a linked session
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'proposalAuthorID'::uuid, :'proposalCoSpeakerID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":2,"skipped_count":0}'::jsonb,
    'Should award the CFS proposal speakers of a linked session'
);
select test_process_badge_award_jobs();

-- Should deduplicate recipients before skipping an active attendee
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'attendeeID'::uuid, :'attendeeID'::uuid],
        :'eventID'
    )::jsonb,
    '{"queued_count":0,"skipped_count":1}'::jsonb,
    'Should deduplicate recipients before skipping an active attendee'
);

-- Should award an accepted group team member without an event
select is(
    award_badge(
        :'actorID',
        :'communityID',
        :'groupID',
        :'badgeID',
        array[:'teamMemberID'::uuid],
        null
    )::jsonb,
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should award an accepted group team member without an event'
);
select test_process_badge_award_jobs();

-- Should require at least one recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, '{}'::uuid[], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'eventID'
    ),
    'OCG01',
    'badge recipients cannot be empty',
    'Should require at least one recipient'
);

-- Should reject a mixed list when one recipient is ineligible
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid, %L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'attendeeID', :'outsiderID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a mixed list when one recipient is ineligible'
);

-- Should reject a null recipient array
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, null, %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'emptyEventID'
    ),
    'OCG01',
    'badge recipients cannot be empty',
    'Should reject a null recipient array'
);

-- Should reject a canceled event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'attendeeID', :'canceledEventID'
    ),
    'OCG01',
    'event not found',
    'Should reject a canceled event'
);

-- Should reject an unknown badge definition
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'unknownBadgeID', :'attendeeID', :'eventID'
    ),
    'OCG01',
    'badge not found',
    'Should reject an unknown badge definition'
);

-- Should reject an unknown group boundary
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', gen_random_uuid(), :'badgeID', :'attendeeID', :'eventID'
    ),
    'OCG01',
    'group not found',
    'Should reject an unknown group boundary'
);

-- Should reject an unknown recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[gen_random_uuid()], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject an unknown recipient'
);

-- Should reject an unverified recipient
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'unverifiedID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject an unverified recipient'
);

-- Should reject a recipient outside the event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], %L::uuid)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'outsiderID', :'eventID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a recipient outside the event'
);

-- Should reject a non-team group member without an event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], null)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'groupMemberID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a non-team group member without an event'
);

-- Should reject a pending group team member without an event
select throws_ok(
    format(
        $$select award_badge(%L::uuid, %L::uuid, %L::uuid, %L::uuid, array[%L::uuid], null)$$,
        :'actorID', :'communityID', :'groupID', :'badgeID', :'outsiderID'
    ),
    'OCG01',
    'badge recipient is not eligible',
    'Should reject a pending group team member without an event'
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

-- Should enqueue one notification for an awarded attendee and none for skipped awards
select is(
    (select count(*)::integer from notification where kind = 'badge-awarded' and user_id = :'attendeeID'),
    1,
    'Should enqueue one notification for an awarded attendee and none for skipped awards'
);

-- Should write issuance audit history after insertion
select results_eq(
    format(
        $$
            select
                al.action,
                al.actor_user_id,
                al.actor_username,
                al.community_id,
                al.details,
                al.event_id,
                al.group_id,
                al.resource_type
            from audit_log al
            join user_badge ub on ub.user_badge_id = al.resource_id
            where al.action = 'badge_awarded'
            and ub.user_id = %L::uuid
        $$,
        :'attendeeID'
    ),
    format(
        $$
            values (
                'badge_awarded',
                %L::uuid,
                'actor-award-badge',
                %L::uuid,
                '{"badge_name": "Attendee"}'::jsonb,
                %L::uuid,
                %L::uuid,
                'user_badge'
            )
        $$,
        :'actorID', :'communityID', :'eventID', :'groupID'
    ),
    'Should write issuance audit history after insertion'
);

-- Should reuse the group status list while it has capacity
select is(
    (select count(*)::integer from badge_status_list where group_id = :'groupID'),
    1,
    'Should reuse the group status list while it has capacity'
);

-- Revoke and re-award walk: each step below depends on the previous one

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
    '{"queued_count":1,"skipped_count":0}'::jsonb,
    'Should allow a new credential after permanent revocation'
);
select test_process_badge_award_jobs();

-- Should retain revoked history after a re-award
select is(
    (select count(*)::integer from user_badge where badge_id = :'badgeID' and user_id = :'attendeeID'),
    2,
    'Should retain revoked history after a re-award'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
