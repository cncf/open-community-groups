begin;
select plan(9);

-- Test: Returns null for placeholder text - PLEASE ADD A DESCRIPTION HERE
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE ADD A DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE ADD A DESCRIPTION HERE placeholder'
);

-- Test: Returns null for placeholder text - DESCRIPTION GOES HERE
select is(
    format_group_description('{"name": "Test Group", "description": "Some text DESCRIPTION GOES HERE and more"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for DESCRIPTION GOES HERE placeholder'
);

-- Test: Returns null for placeholder text - ADD DESCRIPTION HERE
select is(
    format_group_description('{"name": "Test Group", "description": "ADD DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for ADD DESCRIPTION HERE placeholder'
);

-- Test: Returns null for placeholder text - PLEASE UPDATE THE BELOW DESCRIPTION
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE UPDATE THE BELOW DESCRIPTION: old text"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE UPDATE THE BELOW DESCRIPTION placeholder'
);

-- Test: Returns null for placeholder text - PLEASE UPDATE THE DESCRIPTION HERE
select is(
    format_group_description('{"name": "Test Group", "description": "PLEASE UPDATE THE DESCRIPTION HERE"}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should return null for PLEASE UPDATE THE DESCRIPTION HERE placeholder'
);

-- Test: Handles null description
select is(
    format_group_description('{"name": "Test Group", "description": null}'::json)::jsonb,
    '{"name": "Test Group"}'::jsonb,
    'Should handle null description gracefully'
);

-- Test: Strips HTML tags from valid description
select is(
    format_group_description('{"name": "Test Group", "description": "<p>This is a <strong>test</strong> description</p>"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is a test description"}'::jsonb,
    'Should strip HTML tags from description'
);

-- Test: Replaces &nbsp; with spaces
select is(
    format_group_description('{"name": "Test Group", "description": "Test&nbsp;with&nbsp;spaces"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Test with spaces"}'::jsonb,
    'Should replace &nbsp; with spaces'
);

-- Test: Truncates long descriptions to 500 characters
select ok(
    length(format_group_description(jsonb_build_object('name', 'Test Group', 'description', repeat('a', 600))::json)->>'description') = 500,
    'Should truncate long descriptions to 500 characters'
);

select * from finish();
rollback;
