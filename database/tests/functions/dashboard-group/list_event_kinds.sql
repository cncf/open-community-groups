-- Start transaction and plan tests
begin;
select plan(1);

-- Test: list_event_kinds returns all three event kinds
select is(
    list_event_kinds()::jsonb,
    '[
        {
            "event_kind_id": "hybrid",
            "display_name": "Hybrid"
        },
        {
            "event_kind_id": "in-person",
            "display_name": "In Person"
        },
        {
            "event_kind_id": "virtual",
            "display_name": "Virtual"
        }
    ]'::jsonb,
    'list_event_kinds should return all three event kinds ordered by event_kind_id'
);

-- Finish tests and rollback transaction
select * from finish();
rollback;