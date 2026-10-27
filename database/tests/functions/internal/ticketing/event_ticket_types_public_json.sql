-- Tests keeping the attendee-visible public tiers of a ticket type list.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(4);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should keep only public tiers in their original order
select is(
    event_ticket_types_public_json('[
        {"availability": "public", "title": "Late bird"},
        {"availability": "invitation_only", "title": "Speaker"},
        {"availability": "public", "title": "Early bird"}
    ]'::jsonb),
    '[
        {"availability": "public", "title": "Late bird"},
        {"availability": "public", "title": "Early bird"}
    ]'::jsonb,
    'Should keep only public tiers in their original order'
);

-- Should return null for a null list
select ok(
    event_ticket_types_public_json(null) is null,
    'Should return null for a null list'
);

-- Should return null for an empty list
select ok(
    event_ticket_types_public_json('[]'::jsonb) is null,
    'Should return null for an empty list'
);

-- Should return null when every tier is invitation-only
select ok(
    event_ticket_types_public_json('[
        {"availability": "invitation_only", "title": "Speaker"},
        {"availability": "invitation_only", "title": "Sponsor"}
    ]'::jsonb) is null,
    'Should return null when every tier is invitation-only'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
