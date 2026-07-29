-- Tests accepting exact non-ticketed organizer admission offers.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(8);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set admissionOfferID '4a170000-0000-0000-0000-000000000001'
\set communityID '4a170000-0000-0000-0000-000000000002'
\set currentOfferID '4a170000-0000-0000-0000-000000000003'
\set eventCategoryID '4a170000-0000-0000-0000-000000000004'
\set eventID '4a170000-0000-0000-0000-000000000005'
\set groupCategoryID '4a170000-0000-0000-0000-000000000006'
\set groupID '4a170000-0000-0000-0000-000000000007'
\set invitedUserID '4a170000-0000-0000-0000-000000000008'
\set questionID '4a170000-0000-0000-0000-000000000009'
\set staleOfferID '4a170000-0000-0000-0000-00000000000a'
\set staleUserID '4a170000-0000-0000-0000-00000000000b'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Community hosting the RSVP offer scenarios
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
    'exact-offer-community',
    'Exact Offer Community',
    'Community for exact RSVP offer acceptance tests',
    'https://example.com/banner-mobile.png',
    'https://example.com/banner.png',
    'https://example.com/logo.png'
);

-- Event category used by the RSVP event
insert into event_category (event_category_id, community_id, name)
values (:'eventCategoryID', :'communityID', 'Meetup');

-- Group category used by the hosting group
insert into group_category (group_category_id, community_id, name)
values (:'groupCategoryID', :'communityID', 'Technology');

-- Group hosting the RSVP event
insert into "group" (group_id, community_id, group_category_id, name, slug)
values (
    :'groupID',
    :'communityID',
    :'groupCategoryID',
    'Exact Offer Group',
    'exact-offer-group'
);

-- Users owning active and stale RSVP offers
insert into "user" (user_id, auth_hash, email, email_verified, username) values
    (
        :'invitedUserID',
        'hash-invited',
        'invited@example.test',
        true,
        'invited-user'
    ),
    (
        :'staleUserID',
        'hash-stale',
        'stale@example.test',
        true,
        'stale-user'
    );

-- RSVP event requiring registration answers at claim time
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
    'RSVP event for exact offer acceptance',
    :'eventCategoryID',
    'in-person',
    :'groupID',
    'Exact Offer Event',
    true,
    format(
        '[{"id": "%s", "kind": "free-text", "prompt": "Note", "required": true, "options": []}]',
        :'questionID'
    )::jsonb,
    'exact-offer-event',
    current_timestamp + interval '1 day',
    'UTC'
);

-- Active organizer invitation accepted by the successful scenario
insert into admission_offer (
    admission_offer_id,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'admissionOfferID',
    :'eventID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'invitedUserID'
);

-- Historical expired offer used to prove stale identifiers remain stale
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'staleOfferID',
    current_timestamp - interval '2 hours',
    :'eventID',
    current_timestamp - interval '1 hour',
    'organizer_invitation',
    'expired',
    :'staleUserID'
);

-- Replacement active offer that a stale route must not claim
insert into admission_offer (
    admission_offer_id,
    event_id,
    expires_at,
    source,
    status,
    user_id
) values (
    :'currentOfferID',
    :'eventID',
    current_timestamp + interval '1 hour',
    'organizer_invitation',
    'pending',
    :'staleUserID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should reject a claim without required registration answers
select throws_ok(
    format(
        'select accept_event_admission_offer(%L::uuid, %L::uuid)',
        :'invitedUserID',
        :'admissionOfferID'
    ),
    'questionnaire answers are required',
    'Should reject a claim without required registration answers'
);

-- Should reject a stale offer identifier without claiming its replacement
select is(
    accept_event_admission_offer(
        :'staleUserID'::uuid,
        :'staleOfferID'::uuid
    ),
    '{"conflict":"admission-offer-unavailable"}'::jsonb,
    'Should reject a stale offer identifier'
);

select is(
    (select status from admission_offer where admission_offer_id = :'currentOfferID'),
    'pending',
    'Should leave the replacement offer pending'
);

-- Should accept the exact owned offer with registration answers
select is(
    accept_event_admission_offer(
        :'invitedUserID',
        :'admissionOfferID',
        format(
            '{"answers": [{"question_id": "%s", "value": "Answer"}]}',
            :'questionID'
        )::jsonb
    ),
    jsonb_build_object(
        'community_id', :'communityID'::uuid,
        'event_id', :'eventID'::uuid
    ),
    'Should return notification context for the accepted offer'
);

select results_eq(
    format(
        $$
            select
                manually_invited,
                registration_answers,
                status
            from event_attendee
            where event_id = %L::uuid
            and user_id = %L::uuid
        $$,
        :'eventID',
        :'invitedUserID'
    ),
    format(
        $$
            values (
                true,
                '{"answers": [{"question_id": "%s", "value": "Answer"}]}'::jsonb,
                'confirmed'::text
            )
        $$,
        :'questionID'
    ),
    'Should create manually invited attendance with validated answers'
);

select is(
    (select status from admission_offer where admission_offer_id = :'admissionOfferID'),
    'completed',
    'Should complete the exact admission offer'
);

-- Should record the accepted offer decision
select ok(
    exists (
        select 1
        from audit_log al
        where al.action = 'event_attendee_invitation_accepted'
        and al.event_id = :'eventID'
        and al.resource_id = :'invitedUserID'
    ),
    'Should create the invitation acceptance audit row'
);

-- Should reject replay after the exact offer is completed
select is(
    accept_event_admission_offer(
        :'invitedUserID'::uuid,
        :'admissionOfferID'::uuid
    ),
    '{"conflict":"admission-offer-unavailable"}'::jsonb,
    'Should reject replay after the offer is completed'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
