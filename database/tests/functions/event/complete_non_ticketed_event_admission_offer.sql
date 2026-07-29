-- Tests claiming non-ticketed and grandfathered organizer invitation offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '4a150000-0000-0000-0000-000000000001'
\set eventCategoryID '4a150000-0000-0000-0000-000000000002'
\set eventID '4a150000-0000-0000-0000-000000000003'
\set expiredUserID '4a150000-0000-0000-0000-000000000004'
\set groupCategoryID '4a150000-0000-0000-0000-000000000005'
\set groupID '4a150000-0000-0000-0000-000000000006'
\set invitedUserID '4a150000-0000-0000-0000-000000000007'
\set questionID '4a150000-0000-0000-0000-000000000008'
\set questionsEventID '4a150000-0000-0000-0000-000000000009'
\set questionsUserID '4a150000-0000-0000-0000-00000000000a'
\set replacementOfferID '4a150000-0000-0000-0000-00000000000e'
\set replacementUserID '4a150000-0000-0000-0000-00000000000f'
\set staleOfferID '4a150000-0000-0000-0000-000000000010'
\set ticketedEventID '4a150000-0000-0000-0000-00000000000b'
\set ticketedLegacyOfferID '4a150000-0000-0000-0000-000000000011'
\set ticketedLegacyUserID '4a150000-0000-0000-0000-000000000012'
\set ticketedUserID '4a150000-0000-0000-0000-00000000000c'
\set ticketTypeID '4a150000-0000-0000-0000-00000000000d'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community
insert into community (
    community_id,
    name,
    display_name,
    description,
    banner_mobile_url,
    banner_url,
    logo_url
) values (
    :'communityID',
    'offer-claim-community',
    'Offer Claim Community',
    'Community for organizer invitation offer claim tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Categories
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Offer Claim Group',
    'offer-claim-group'
);

-- Offer recipients
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (:'expiredUserID', 'hash-expired', 'expired@example.test', true, 'expired-user'),
    (:'invitedUserID', 'hash-invited', 'invited@example.test', true, 'invited-user'),
    (:'questionsUserID', 'hash-questions', 'questions@example.test', true, 'questions-user'),
    (:'replacementUserID', 'hash-replacement', 'replacement@example.test', true, 'replacement-user'),
    (:'ticketedLegacyUserID', 'hash-ticketed-legacy', 'ticketed-legacy@example.test', true, 'ticketed-legacy-user'),
    (:'ticketedUserID', 'hash-ticketed', 'ticketed@example.test', true, 'ticketed-user');

-- Active RSVP and ticketed events
insert into event (
    event_id,
    description,
    event_category_id,
    event_kind_id,
    group_id,
    name,
    published,
    registration_questions,
    slug,
    starts_at,
    timezone
) values (
    :'eventID',
    'RSVP event for offer claims',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Offer Claim Event',
    true,
    '[]'::jsonb,
    'offer-claim-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    :'questionsEventID',
    'RSVP event with registration questions',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Offer Questions Event',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'offer-questions-event',
    current_timestamp + interval '1 day',
    'UTC'
), (
    :'ticketedEventID',
    'Ticketed event for offer claim routing',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Ticketed Offer Event',
    true,
    '[]'::jsonb,
    'ticketed-offer-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Ticket type proving ticketed offers stay on the ticket claim path
insert into event_ticket_type (
    event_ticket_type_id,
    event_id,
    "order",
    seats_total,
    title
) values (
    :'ticketTypeID',
    :'ticketedEventID',
    1,
    10,
    'General admission'
);

-- Organizer invitation offers covering active, expired, and ticketed paths
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
    gen_random_uuid(),
    current_timestamp,
    :'eventID',
    null,
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'invitedUserID'
), (
    gen_random_uuid(),
    current_timestamp - interval '2 hours',
    :'eventID',
    null,
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'pending',
    :'expiredUserID'
), (
    gen_random_uuid(),
    current_timestamp,
    :'questionsEventID',
    null,
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'questionsUserID'
), (
    gen_random_uuid(),
    current_timestamp,
    :'ticketedEventID',
    :'ticketTypeID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'ticketedUserID'
), (
    :'staleOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    null,
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'expired',
    :'replacementUserID'
), (
    :'replacementOfferID',
    current_timestamp,
    :'eventID',
    null,
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'replacementUserID'
);

-- Grandfathered ticketed invitation produced by the schema migration
insert into admission_offer (
    admission_offer_id,
    event_id,
    legacy,
    source,
    status,
    user_id
) values (
    :'ticketedLegacyOfferID',
    :'ticketedEventID',
    true,
    'organizer_invitation',
    'pending',
    :'ticketedLegacyUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should complete a valid RSVP organizer invitation
select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'eventID',
        :'invitedUserID'
    ),
    true,
    'Should complete an active non-ticketed organizer invitation'
);

select results_eq(
    format(
        $$
            select manually_invited, status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'invitedUserID'
    ),
    $$ values (true, 'confirmed'::text) $$,
    'Should create confirmed manually invited attendance'
);

select is(
    (
        select status
        from admission_offer
        where event_id = :'eventID'
        and user_id = :'invitedUserID'
    ),
    'completed',
    'Should complete the claimed offer'
);

select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'eventID',
        :'invitedUserID'
    ),
    false,
    'Should return false after the offer has already been claimed'
);

-- Should require registration answers at claim time
select throws_ok(
    format(
        $$
            select complete_non_ticketed_event_admission_offer(
                %L::uuid,
                %L::uuid,
                %L::uuid
            )
        $$,
        :'communityID',
        :'questionsEventID',
        :'questionsUserID'
    ),
    'questionnaire answers are required',
    'Should reject a question-bearing claim without answers'
);

select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'questionsEventID',
        :'questionsUserID',
        format(
            '{"answers": [{"question_id": "%s", "value": "Answer"}]}',
            :'questionID'
        )::jsonb
    ),
    true,
    'Should complete an offer after validating registration answers'
);

select is(
    (
        select registration_answers
        from event_attendee
        where event_id = :'questionsEventID'
        and user_id = :'questionsUserID'
    ),
    format(
        '{"answers": [{"question_id": "%s", "value": "Answer"}]}',
        :'questionID'
    )::jsonb,
    'Should retain validated registration answers'
);

-- Should leave ticketed and expired offers to their owning workflows
select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'ticketedEventID',
        :'ticketedUserID'
    ),
    false,
    'Should return false for ticketed events'
);

-- Should complete a grandfathered ticketed organizer invitation
select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'ticketedEventID',
        :'ticketedLegacyUserID',
        null,
        :'ticketedLegacyOfferID'
    ),
    true,
    'Should complete a grandfathered ticketed organizer invitation'
);

-- Should confirm grandfathered ticketed invitation attendance
select results_eq(
    format(
        $$
            select manually_invited, status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'ticketedEventID',
        :'ticketedLegacyUserID'
    ),
    $$ values (true, 'confirmed'::text) $$,
    'Should confirm grandfathered ticketed invitation attendance'
);

-- Should complete the grandfathered ticketed invitation offer
select is(
    (select status from admission_offer where admission_offer_id = :'ticketedLegacyOfferID'),
    'completed',
    'Should complete the grandfathered ticketed invitation offer'
);

-- Should return false for expired offers
select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'eventID',
        :'expiredUserID'
    ),
    false,
    'Should return false for expired offers'
);

-- Should leave a replacement offer untouched when an exact stale id is supplied
select is(
    complete_non_ticketed_event_admission_offer(
        :'communityID',
        :'eventID',
        :'replacementUserID',
        null,
        :'staleOfferID'
    ),
    false,
    'Should reject an exact stale offer identifier'
);

select is(
    (select status from admission_offer where admission_offer_id = :'replacementOfferID'),
    'pending',
    'Should leave the replacement offer pending'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
