-- Tests searching organizer event waiting lists and offer history.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(14);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set communityID '3a300000-0000-0000-0000-000000000001'
\set canceledOfferID '3a300000-0000-0000-0000-00000000000f'
\set event1ID '3a300000-0000-0000-0000-000000000002'
\set eventOfferID '3a300000-0000-0000-0000-00000000000a'
\set eventCategoryID '3a300000-0000-0000-0000-000000000003'
\set expiredOfferID '3a300000-0000-0000-0000-000000000010'
\set group2ID '3a300000-0000-0000-0000-000000000004'
\set groupCategoryID '3a300000-0000-0000-0000-000000000005'
\set groupID '3a300000-0000-0000-0000-000000000006'
\set missingEventID '3a300000-0000-0000-0000-000000000007'
\set offerID '3a300000-0000-0000-0000-00000000000b'
\set priceWindowID '3a300000-0000-0000-0000-00000000000c'
\set ticketTypeID '3a300000-0000-0000-0000-00000000000d'
\set user1ID '3a300000-0000-0000-0000-000000000008'
\set user2ID '3a300000-0000-0000-0000-000000000009'
\set user3ID '3a300000-0000-0000-0000-00000000000e'

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
    'bio', 'Waits for event capacity',
    'company', 'Cloud Corp',
    'github_url', 'https://github.com/alice',
    'name', 'Alice',
    'photo_url', 'https://example.com/alice.png',
    'provider', '{"github": {"username": "alice-gh", "private": "secret"}, "linuxfoundation": {"username": "alice-lf", "subject": "secret"}}'::jsonb,
    'title', 'Principal Engineer',
    'username', 'alice-search-event-waitlist',
    'website_url', 'https://example.com/alice'
));
select fx_user(:'user2ID', jsonb_build_object(
    'photo_url', 'https://example.com/bob.png',
    'username', 'bob-search-event-waitlist'
));
select fx_user(:'user3ID', jsonb_build_object(
    'name', 'Carol',
    'username', 'carol-search-event-waitlist'
));

-- Event
select fx_event(:'event1ID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));
select fx_event(:'eventOfferID', :'groupID', :'eventCategoryID', jsonb_build_object(
    'capacity', 1,
    'published', true,
    'waitlist_enabled', true
));

-- Ticket type assigned to the promoted-offer event
select fx_event_ticket_type(:'ticketTypeID', :'eventOfferID', jsonb_build_object(
    'seats_total', 1,
    'title', 'General admission'
));

-- Free price window for the promoted-offer ticket type
select fx_event_ticket_price_window(:'priceWindowID', :'ticketTypeID', jsonb_build_object('amount_minor', 0));

-- Events without an explicit ticket fixture use default admission tiers
select fx_event_ticket_type(gen_random_uuid(), e.event_id, jsonb_build_object(
    'seats_total', 100,
    'title', 'General Admission'
))
from event e
where not exists (
    select 1
    from event_ticket_type ett
    where ett.event_id = e.event_id
);

-- Capture the first event's synthesized ticket tier
select event_ticket_type_id as "event1TicketTypeID"
from event_ticket_type
where event_id = :'event1ID'
\gset

-- Waitlist entries
insert into event_waitlist (event_id, event_ticket_type_id, user_id, created_at)
values
    (
        :'event1ID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'event1ID' limit 1),
        :'user1ID',
        '2024-01-01 00:00:00+00'
    ),
    (
        :'event1ID',
        (select event_ticket_type_id from event_ticket_type where event_id = :'event1ID' limit 1),
        :'user2ID',
        '2024-01-02 00:00:00+00'
    );

-- Waitlist offer history
insert into admission_offer (
    admission_offer_id,
    created_at,
    event_id,
    event_ticket_type_id,
    expires_at,
    source,
    status,
    user_id
) values
    (
        :'expiredOfferID',
        '2024-01-01 00:00:00+00',
        :'eventOfferID',
        :'ticketTypeID',
        '2024-01-02 00:00:00+00',
        'waitlist',
        'expired',
        :'user1ID'
    ),
    (
        :'offerID',
        '2024-01-03 00:00:00+00',
        :'eventOfferID',
        :'ticketTypeID',
        '2099-01-03 10:00:00+00',
        'waitlist',
        'pending',
        :'user3ID'
    ),
    (
        :'canceledOfferID',
        '2024-01-04 00:00:00+00',
        :'eventOfferID',
        :'ticketTypeID',
        '2024-01-05 00:00:00+00',
        'waitlist',
        'canceled',
        :'user2ID'
    );

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should return waitlist entries with expected fields and FIFO order by default
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', format('[
            {"created_at": 1704067200, "event_ticket_type_id": "%s", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000008", "username": "alice-search-event-waitlist", "bio": "Waits for event capacity", "company": "Cloud Corp", "github_url": "https://github.com/alice", "name": "Alice", "photo_url": "https://example.com/alice.png", "provider": {"github": {"username": "alice-gh"}, "linuxfoundation": {"username": "alice-lf"}}, "title": "Principal Engineer", "website_url": "https://example.com/alice"}, "waitlist_position": 1},
            {"created_at": 1704153600, "event_ticket_type_id": "%s", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob-search-event-waitlist", "photo_url": "https://example.com/bob.png"}, "waitlist_position": 2}
        ]', :'event1TicketTypeID', :'event1TicketTypeID')::jsonb,
        'total', 2
    ),
    'Should return waitlist entries with expected fields and FIFO order by default'
);

-- Should expose offer history promoted from the ticket waitlist
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'eventOfferID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    format(
        $json$
        {
            "total": 3,
            "waitlist": [
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "expired",
                    "created_at": 1704067200,
                    "event_ticket_type_id": "%s",
                    "offer_expires_at": 1704153600,
                    "ticket_title": "General admission",
                    "user": {
                        "bio": "Waits for event capacity",
                        "company": "Cloud Corp",
                        "github_url": "https://github.com/alice",
                        "name": "Alice",
                        "photo_url": "https://example.com/alice.png",
                        "provider": {
                            "github": {
                                "username": "alice-gh"
                            },
                            "linuxfoundation": {
                                "username": "alice-lf"
                            }
                        },
                        "title": "Principal Engineer",
                        "user_id": "%s",
                        "username": "alice-search-event-waitlist",
                        "website_url": "https://example.com/alice"
                    },
                    "waitlist_position": null
                },
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "pending",
                    "created_at": 1704240000,
                    "event_ticket_type_id": "%s",
                    "offer_expires_at": 4071117600,
                    "ticket_title": "General admission",
                    "user": {
                        "name": "Carol",
                        "user_id": "%s",
                        "username": "carol-search-event-waitlist"
                    },
                    "waitlist_position": null
                },
                {
                    "admission_offer_id": "%s",
                    "admission_offer_status": "canceled",
                    "created_at": 1704326400,
                    "event_ticket_type_id": "%s",
                    "offer_expires_at": 1704412800,
                    "ticket_title": "General admission",
                    "user": {
                        "photo_url": "https://example.com/bob.png",
                        "user_id": "%s",
                        "username": "bob-search-event-waitlist"
                    },
                    "waitlist_position": null
                }
            ]
        }
        $json$,
        :'expiredOfferID',
        :'ticketTypeID',
        :'user1ID',
        :'offerID',
        :'ticketTypeID',
        :'user3ID',
        :'canceledOfferID',
        :'ticketTypeID',
        :'user2ID'
    )::jsonb,
    'Should expose offer history promoted from the ticket waitlist'
);

-- Should return paginated waitlist entries when limit and offset are provided
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 1, 'offset', 1)
    )::jsonb,
    jsonb_build_object(
        'waitlist', format('[
            {"created_at": 1704153600, "event_ticket_type_id": "%s", "ticket_title": "General Admission", "user": {"user_id": "3a300000-0000-0000-0000-000000000009", "username": "bob-search-event-waitlist", "photo_url": "https://example.com/bob.png"}, "waitlist_position": 2}
        ]', :'event1TicketTypeID')::jsonb,
        'total', 2
    ),
    'Should return paginated waitlist entries when limit and offset are provided'
);

-- Should return empty list when event scope is null
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        null::uuid,
        '{"limit":50,"offset":0}'::jsonb
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event scope is null'
);

-- Should return empty list for non-existing event
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'missingEventID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list for non-existing event'
);

-- Should return empty list when event belongs to another group
select is(
    search_event_waitlist(
        :'group2ID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object('limit', 50, 'offset', 0)
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return empty list when event belongs to another group'
);

-- Should filter waitlist entries by identity search query
select ok(
    (
        with result as (
            select search_event_waitlist(
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
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by identity search query'
);

-- Should filter waitlist entries by company search query
select ok(
    (
        with result as (
            select search_event_waitlist(
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
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by company search query'
);

-- Should filter waitlist entries by title search query
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'principal engineer'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by title search query'
);

-- Should sort waitlist entries by name ascending
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'name-asc'
        )
    )::jsonb#>>'{waitlist,0,user,username}',
    'alice-search-event-waitlist',
    'Should sort waitlist entries by name ascending'
);

-- Should sort waitlist entries by joined date descending
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'sort', 'created-at-desc'
        )
    )::jsonb#>>'{waitlist,0,user,username}',
    'bob-search-event-waitlist',
    'Should sort waitlist entries by joined date descending'
);

-- Should filter waitlist entries by title presence
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'title', 'present'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user1ID'
        and data#>>'{waitlist,0,waitlist_position}' = '1'
        from result
    ),
    'Should filter waitlist entries by title presence'
);

-- Should keep real waitlist position when search filters earlier entries
select ok(
    (
        with result as (
            select search_event_waitlist(
                :'groupID'::uuid,
                :'event1ID'::uuid,
                jsonb_build_object(
                    'limit', 50,
                    'offset', 0,
                    'ts_query', 'bob-search-event-waitlist'
                )
            )::jsonb as data
        )
        select (data->>'total')::int = 1
        and data#>>'{waitlist,0,user,user_id}' = :'user2ID'
        and data#>>'{waitlist,0,waitlist_position}' = '2'
        from result
    ),
    'Should keep real waitlist position when search filters earlier entries'
);

-- Should return no waitlist entries when search has no matches
select is(
    search_event_waitlist(
        :'groupID'::uuid,
        :'event1ID'::uuid,
        jsonb_build_object(
            'limit', 50,
            'offset', 0,
            'ts_query', 'missing person'
        )
    )::jsonb,
    jsonb_build_object(
        'waitlist', '[]'::jsonb,
        'total', 0
    ),
    'Should return no waitlist entries when search has no matches'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
