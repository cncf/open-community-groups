-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(9);

-- ============================================================================
-- TESTS
-- ============================================================================

-- Placeholder text 'PLEASE ADD A DESCRIPTION HERE' returns null
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE ADD A DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE ADD A DESCRIPTION HERE placeholder'
);

-- Placeholder text 'DESCRIPTION GOES HERE' returns null
select is(
    format_group_description('{"name": "Test Group", "description": "Some text DESCRIPTION GOES HERE and more"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for DESCRIPTION GOES HERE placeholder'
);

-- Placeholder text 'ADD DESCRIPTION HERE' returns null
select is(
    format_group_description('{"name": "Test Group", "description": "ADD DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for ADD DESCRIPTION HERE placeholder'
);

-- Placeholder text 'PLEASE UPDATE THE BELOW DESCRIPTION' returns null
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE UPDATE THE BELOW DESCRIPTION: old text"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE UPDATE THE BELOW DESCRIPTION placeholder'
);

-- Placeholder text 'PLEASE UPDATE THE DESCRIPTION HERE' returns null
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE UPDATE THE DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE UPDATE THE DESCRIPTION HERE placeholder'
);

-- Null description handled gracefully
select is(
    format_group_description('{"name": "Test Group", "description": null}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should handle null description gracefully'
);

-- HTML tags stripped from description
select is(
    format_group_description('{"name": "Test Group", "description": "<p>This is a <strong>test</strong> description</p>"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is a test description"}'::jsonb,
    'Should strip HTML tags from description'
);

-- HTML entity &nbsp; replaced with spaces
select is(
    format_group_description('{"name": "Test Group", "description": "Test&nbsp;with&nbsp;spaces"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Test with spaces"}'::jsonb,
    'Should replace &nbsp; with spaces'
);

-- Long descriptions truncated to 500 characters
select ok(
    length(format_group_description(jsonb_build_object('name', 'Test Group', 'description', repeat('a', 600))::json)->>'description') = 500,
    'Should truncate long descriptions to 500 characters'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
