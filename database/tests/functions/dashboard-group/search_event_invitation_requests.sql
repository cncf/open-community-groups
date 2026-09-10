-- Tests searching organizer event invitation requests.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a2f0000-0000-0000-0000-000000000001'
\set event1ID '3a2f0000-0000-0000-0000-000000000002'
\set event2ID '3a2f0000-0000-0000-0000-000000000003'
\set eventCategoryID '3a2f0000-0000-0000-0000-000000000004'
\set expiredOfferID '3a2f0000-0000-0000-0000-000000000015'
\set group2ID '3a2f0000-0000-0000-0000-000000000005'
\set groupCategoryID '3a2f0000-0000-0000-0000-000000000006'
\set groupID '3a2f0000-0000-0000-0000-000000000007'
\set missingEventID '3a2f0000-0000-0000-0000-000000000008'
\set offerID '3a2f0000-0000-0000-0000-000000000012'
\set priceWindowID '3a2f0000-0000-0000-0000-000000000013'
\set priceWindow2ID '3a2f0000-0000-0000-0000-000000000016'
\set ticketTypeID '3a2f0000-0000-0000-0000-000000000014'
\set ticketType2ID '3a2f0000-0000-0000-0000-000000000017'
\set user1ID '3a2f0000-0000-0000-0000-000000000009'
\set user2ID '3a2f0000-0000-0000-0000-000000000010'
\set user3ID '3a2f0000-0000-0000-0000-000000000011'

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Baseline communities, group categories and groups
select fx_community(:'communityID');
select fx_group_category(:'groupCategoryID', :'communityID');
select fx_group(:'group2ID', :'communityID', :'groupCategoryID');
select fx_group(:'groupID', :'communityID', :'groupCategoryID');

-- Event category
select fx_event_category(:'eventCategoryID', :'communityID', jsonb_build_object('name', 'General'));

-- Users
select fx_user(:'user1ID', jsonb_build_object(
    'bio', 'Reviews invitation requests',
    'company', 'Cloud Corp',
    'github_url', 'https://github.com/alice',
    'name', 'Alice',
    'photo_url', 'https://example.com/alice.png',
    'provider', '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    'title', 'Principal Engineer',
    'username', 'alice-search-event-invitation-requests',
    'website_url', 'https://example.com/alice'
));
select fx_user(:'user2ID', jsonb_build_object(
    'photo_url', 'https://example.com/bob.png',
    'username', 'bob-search-event-invitation-requests'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'Carol',
    'title', 'Designer',
    'username', 'carol'
));

-- Events
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));
select fx_event(:'event2ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'attendee_approval_required', true,
    'published', true
));

-- Public ticket tier requested by an accepted attendee
select fx_event_ticket_type(:'ticketTypeID', :'event1ID', jsonb_build_object(
    'seats_total', 10,
    'title', 'General admission'
));
select fx_event_ticket_type(:'ticketType2ID', :'event2ID', jsonb_build_object(
    'availability', 'invitation_only',
    'seats_total', 10,
    'title', 'Private admission'
));

-- Free price windows for the request ticket tiers
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));
select fx_event_ticket_price_window(:'priceWindow2ID', :'ticketType2ID', jsonb_build_object('amount_minor', 0));

-- Invitation requests
insert into event_invitation_request (
    event_id,
    event_ticket_type_id,
    user_id,
    created_at,
    registration_answers,
    reviewed_at,
    reviewed_by,
    status
) values (
    :'event1ID',
    :'ticketTypeID',
    :'user1ID',
    '2024-01-01 00:00:00+00',
    null,
    '2024-01-01 01:00:00+00',
    :'user3ID',
    'accepted'
), (
    :'event1ID',
    :'ticketTypeID',
    :'user2ID',
    '2024-01-02 00:00:00+00',
    '{"answers": [{"question_id": "3a2f0000-0000-0000-0000-000000000018", "value": "Vegetarian"}]}',
    null,
    null,
    'pending'
), (
    :'event1ID',
    :'ticketTypeID',
    :'user3ID',
    '2024-01-03 00:00:00+00',
    null,
    '2024-01-03 01:00:00+00',
    :'user1ID',
    'rejected'
), (
    :'event2ID',
    null,
    :'user3ID',
    '2024-01-04 00:00:00+00',
    null,
    '2024-01-04 01:00:00+00',
    :'user1ID',
    'accepted'
);

-- Active approval offer returned with its request
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
    :'event1ID',
    :'ticketTypeID',
    '2099-01-10 00:00:00+00',
    :'user3ID',
    'approval',
    'pending',
    :'user1ID'
);

-- Expired approval offer retained with its accepted request
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    organizer_user_id,
    source,
    status,
    user_id
) values (
    :'expiredOfferID',
    '2024-01-04 02:00:00+00',
    :'event2ID',
    :'ticketType2ID',
    '2024-01-05 00:00:00+00',
    :'user1ID',
    'approval',
    'expired',
    :'user3ID'
);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return invitation requests by requested date descending by default
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704240000, "invitation_request_status": "rejected", "requested_event_ticket_type_id": "3a2f0000-0000-0000-0000-000000000014", "requested_ticket_title": "General admission", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000011", "username": "carol", "name": "Carol", "title": "Designer"}, "reviewed_at": 1704243600},
            {"created_at": 1704153600, "invitation_request_status": "pending", "requested_event_ticket_type_id": "3a2f0000-0000-0000-0000-000000000014", "requested_ticket_title": "General admission", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000010", "username": "bob-search-event-invitation-requests", "photo_url": "https://example.com/bob.png"}, "reviewed_at": null, "registration_answers": {"answers": [{"question_id": "3a2f0000-0000-0000-0000-000000000018", "value": "Vegetarian"}]}},
            {"admission_offer_id": "3a2f0000-0000-0000-0000-000000000012", "admission_offer_status": "pending", "created_at": 1704067200, "invitation_request_status": "accepted", "offer_expires_at": 4071686400, "offered_event_ticket_type_id": "3a2f0000-0000-0000-0000-000000000014", "offered_ticket_title": "General admission", "requested_event_ticket_type_id": "3a2f0000-0000-0000-0000-000000000014", "requested_ticket_title": "General admission", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000009", "username": "alice-search-event-invitation-requests", "bio": "Reviews invitation requests", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "reviewed_at": 1704070800}
        ]'::jsonb,
        'total', 3
    ),
    'Should return invitation requests by requested date descending by default'
);

-- Should retain the latest expired approval offer for reissue
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event2ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    format(
        $json$
        {
            "invitation_requests": [
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "expired",
                    "created_at": 1704326400,
                    "invitation_request_status": "accepted",
                    "offer_expires_at": 1704412800,
                    "offered_event_ticket_type_id": "%s",
                    "offered_ticket_title": "Private admission",
                    "requested_event_ticket_type_id": null,
                    "requested_ticket_title": null,
                    "reviewed_at": 1704330000,
                    "user": {
                        "name": "Carol",
                        "title": "Designer",
                        "user_id": "%s",
                        "username": "carol"
                    }
                }
            ],
            "total": 1
        }
        $json$,
        :'expiredOfferID',
        :'ticketType2ID',
        :'user3ID'
    )::jsonb,
    'Should retain the latest expired approval offer for reissue'
);

-- Should return paginated invitation requests when limit and offset are provided
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[
            {"created_at": 1704153600, "invitation_request_status": "pending", "requested_event_ticket_type_id": "3a2f0000-0000-0000-0000-000000000014", "requested_ticket_title": "General admission", "user": {"user_id": "3a2f0000-0000-0000-0000-000000000010", "username": "bob-search-event-invitation-requests", "photo_url": "https://example.com/bob.png"}, "reviewed_at": null, "registration_answers": {"answers": [{"question_id": "3a2f0000-0000-0000-0000-000000000018", "value": "Vegetarian"}]}}
        ]'::jsonb,
        'total', 3
    ),
    'Should return paginated invitation requests when limit and offset are provided'
);

-- Should return empty list when event scope is null
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_invitation_requests(
        :'group2ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter invitation requests by identity search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'ali'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter invitation requests by identity search query'
);

-- Should filter invitation requests by company search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'cloud corp'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user1ID'
        from result
    ),
    'Should filter invitation requests by company search query'
);

-- Should filter invitation requests by title search query
select ok(
    (
        with result as (
            select search_event_invitation_requests(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'designer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{invitation_requests,0,user,user_id}' = :'user3ID'
        from result
    ),
    'Should filter invitation requests by title search query'
);

-- Should sort invitation requests by requester name ascending
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'name-asc'
        )
    )::jsonb#>>'{invitation_requests,0,user,username}',
    'alice-search-event-invitation-requests',
    'Should sort invitation requests by requester name ascending'
);

-- Should filter invitation requests by status
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'status', 'pending'
        )
    )::jsonb->>'total',
    '1',
    'Should filter invitation requests by status'
);

-- Should filter invitation requests by title presence
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'title', 'present'
        )
    )::jsonb->>'total',
    '2',
    'Should filter invitation requests by title presence'
);

-- Should include registration answers when present
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'status', 'pending'
        )
    )::jsonb#>'{invitation_requests,0,registration_answers}',
    '{"answers": [{"question_id": "3a2f0000-0000-0000-0000-000000000018", "value": "Vegetarian"}]}'::jsonb,
    'Should include registration answers when present'
);

-- Should return no invitation requests when search has no matches
select is(
    search_event_invitation_requests(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'ts_query', 'missing person'
        )
    )::jsonb,
    jsonb_build_object(
        'invitation_requests', '[]'::jsonb,
        'total', 0
    ),
    'Should return no invitation requests when search has no matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
