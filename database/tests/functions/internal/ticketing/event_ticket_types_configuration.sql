-- Tests projecting ticket type payloads onto their comparable configuration.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(7);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set earlyWindowID '3b050000-0000-0000-0000-000000000001'
\set generalTicketTypeID '3b050000-0000-0000-0000-000000000002'
\set lateWindowID '3b050000-0000-0000-0000-000000000003'
\set vipTicketTypeID '3b050000-0000-0000-0000-000000000004'
\set vipWindowID '3b050000-0000-0000-0000-000000000005'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should default a missing price_windows key to an empty array
select is(
    event_ticket_types_configuration(
        format('[{"event_ticket_type_id": "%s", "title": "General"}]', :'generalTicketTypeID')::jsonb
    ),
    format('[{"event_ticket_type_id": "%s", "price_windows": [], "title": "General"}]', :'generalTicketTypeID')::jsonb,
    'Should default a missing price_windows key to an empty array'
);

-- Should keep tier and window order while normalizing every window
select is(
    event_ticket_types_configuration(
        format('[
            {
                "active": true,
                "availability": "public",
                "event_ticket_type_id": "%s",
                "order": 2,
                "price_windows": [
                    {"amount_minor": 2000, "event_ticket_price_window_id": "%s"}
                ],
                "seats_total": 5,
                "title": "VIP"
            },
            {
                "active": true,
                "availability": "public",
                "event_ticket_type_id": "%s",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "ends_at": "2030-03-01T10:00:00Z",
                        "event_ticket_price_window_id": "%s",
                        "starts_at": "2030-01-01T10:00:00Z"
                    },
                    {
                        "amount_minor": 3000,
                        "ends_at": "2030-06-01T12:00:00+02:00",
                        "event_ticket_price_window_id": "%s",
                        "starts_at": "2030-03-01T10:00:01+00:00"
                    }
                ],
                "seats_total": 10,
                "title": "General"
            }
        ]', :'vipTicketTypeID', :'vipWindowID', :'generalTicketTypeID', :'earlyWindowID', :'lateWindowID')::jsonb
    ),
    format('[
        {
            "active": true,
            "availability": "public",
            "event_ticket_type_id": "%s",
            "order": 2,
            "price_windows": [
                {"amount_minor": 2000, "event_ticket_price_window_id": "%s"}
            ],
            "seats_total": 5,
            "title": "VIP"
        },
        {
            "active": true,
            "availability": "public",
            "event_ticket_type_id": "%s",
            "order": 1,
            "price_windows": [
                {
                    "amount_minor": 2500,
                    "ends_at": 1898589600,
                    "event_ticket_price_window_id": "%s",
                    "starts_at": 1893492000
                },
                {
                    "amount_minor": 3000,
                    "ends_at": 1906538400,
                    "event_ticket_price_window_id": "%s",
                    "starts_at": 1898589601
                }
            ],
            "seats_total": 10,
            "title": "General"
        }
    ]', :'vipTicketTypeID', :'vipWindowID', :'generalTicketTypeID', :'earlyWindowID', :'lateWindowID')::jsonb,
    'Should keep tier and window order while normalizing every window'
);

-- Should project a JSON null payload to an empty array
select is(
    event_ticket_types_configuration('null'::jsonb),
    '[]'::jsonb,
    'Should project a JSON null payload to an empty array'
);

-- Should project a SQL null payload to an empty array
select is(
    event_ticket_types_configuration(null),
    '[]'::jsonb,
    'Should project a SQL null payload to an empty array'
);

-- Should project an empty payload to an empty array
select is(
    event_ticket_types_configuration('[]'::jsonb),
    '[]'::jsonb,
    'Should project an empty payload to an empty array'
);

-- Should strip read-model fields and keep the configuration keys
select is(
    event_ticket_types_configuration(
        format('[
            {
                "active": true,
                "availability": "public",
                "current_price": {"amount_minor": 2500},
                "description": "Main entrance",
                "event_ticket_type_id": "%s",
                "order": 1,
                "price_windows": [
                    {"amount_minor": 2500, "event_ticket_price_window_id": "%s"}
                ],
                "remaining_seats": 7,
                "seats_total": 10,
                "sold_out": false,
                "title": "General"
            }
        ]', :'generalTicketTypeID', :'earlyWindowID')::jsonb
    ),
    format('[
        {
            "active": true,
            "availability": "public",
            "description": "Main entrance",
            "event_ticket_type_id": "%s",
            "order": 1,
            "price_windows": [
                {"amount_minor": 2500, "event_ticket_price_window_id": "%s"}
            ],
            "seats_total": 10,
            "title": "General"
        }
    ]', :'generalTicketTypeID', :'earlyWindowID')::jsonb,
    'Should strip read-model fields and keep the configuration keys'
);

-- Should treat the stored projection and an editor echo with Z spellings as equal
select is(
    event_ticket_types_configuration(
        format('[
            {
                "active": true,
                "availability": "public",
                "current_price": {"amount_minor": 2500, "starts_at": "2030-01-01T12:00:00+02:00"},
                "event_ticket_type_id": "%s",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "%s",
                        "starts_at": "2030-01-01T12:00:00+02:00"
                    }
                ],
                "remaining_seats": 10,
                "seats_total": 10,
                "sold_out": false,
                "title": "General"
            }
        ]', :'generalTicketTypeID', :'earlyWindowID')::jsonb
    ),
    event_ticket_types_configuration(
        format('[
            {
                "active": true,
                "availability": "public",
                "event_ticket_type_id": "%s",
                "order": 1,
                "price_windows": [
                    {
                        "amount_minor": 2500,
                        "event_ticket_price_window_id": "%s",
                        "starts_at": "2030-01-01T10:00:00Z"
                    }
                ],
                "seats_total": 10,
                "title": "General"
            }
        ]', :'generalTicketTypeID', :'earlyWindowID')::jsonb
    ),
    'Should treat the stored projection and an editor echo with Z spellings as equal'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
