-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(25);

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

-- Markdown headers removed
select is(
    format_group_description('{"name": "Test Group", "description": "# Header 1\n## Header 2\n### Header 3\nText content"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Header 1 Header 2 Header 3 Text content"}'::jsonb,
    'Should remove Markdown headers'
);

-- Bold markdown removed
select is(
    format_group_description('{"name": "Test Group", "description": "This is **bold** and __also bold__ text"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is bold and also bold text"}'::jsonb,
    'Should remove bold Markdown syntax'
);

-- Italic markdown removed
select is(
    format_group_description('{"name": "Test Group", "description": "This is *italic* and _also italic_ text"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is italic and also italic text"}'::jsonb,
    'Should remove italic Markdown syntax'
);

-- Bold italic markdown removed
select is(
    format_group_description('{"name": "Test Group", "description": "This is ***bold italic*** and ___also bold italic___ text"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is bold italic and also bold italic text"}'::jsonb,
    'Should remove bold italic Markdown syntax'
);

-- Strikethrough markdown removed (GFM)
select is(
    format_group_description('{"name": "Test Group", "description": "This is ~~strikethrough~~ text"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is strikethrough text"}'::jsonb,
    'Should remove strikethrough Markdown syntax'
);

-- Links - keep text, remove URL
select is(
    format_group_description('{"name": "Test Group", "description": "Visit [our website](https://example.com) for more info"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Visit our website for more info"}'::jsonb,
    'Should keep link text but remove URL'
);

-- Images removed completely
select is(
    format_group_description('{"name": "Test Group", "description": "Here is an image ![alt text](image.png) in the text"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Here is an image in the text"}'::jsonb,
    'Should remove images completely'
);

-- Code blocks removed
select is(
    format_group_description('{"name": "Test Group", "description": "Text before ```python\ncode here\n``` text after"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Text before text after"}'::jsonb,
    'Should remove code blocks'
);

-- Inline code removed
select is(
    format_group_description('{"name": "Test Group", "description": "Use the `command` to run"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Use the to run"}'::jsonb,
    'Should remove inline code'
);

-- Lists markers removed
select is(
    format_group_description('{"name": "Test Group", "description": "- Item 1\n* Item 2\n+ Item 3\n1. First\n2. Second"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Item 1 Item 2 Item 3 First Second"}'::jsonb,
    'Should remove list markers'
);

-- Task lists removed (GFM)
select is(
    format_group_description('{"name": "Test Group", "description": "- [ ] Unchecked\n- [x] Checked\n- [X] Also checked"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Unchecked Checked Also checked"}'::jsonb,
    'Should remove task list markers'
);

-- Blockquotes removed
select is(
    format_group_description('{"name": "Test Group", "description": "> This is a quote\n> Another line"}'::json)::jsonb,
    '{"name": "Test Group", "description": "This is a quote Another line"}'::jsonb,
    'Should remove blockquote markers'
);

-- GitHub alerts removed (GFM)
select is(
    format_group_description('{"name": "Test Group", "description": "> [!NOTE]\n> Important note here"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Important note here"}'::jsonb,
    'Should remove GitHub alert syntax'
);

-- Table formatting removed
select is(
    format_group_description('{"name": "Test Group", "description": "| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1 | Cell 2 |"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Header 1 Header 2 Cell 1 Cell 2"}'::jsonb,
    'Should remove table formatting'
);

-- HTML tags still removed (fallback)
select is(
    format_group_description('{"name": "Test Group", "description": "Text with <strong>HTML</strong> and <em>tags</em>"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Text with HTML and tags"}'::jsonb,
    'Should still remove HTML tags as fallback'
);

-- Mixed Markdown and HTML
select is(
    format_group_description('{"name": "Test Group", "description": "**Markdown bold** and <strong>HTML bold</strong>"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Markdown bold and HTML bold"}'::jsonb,
    'Should remove both Markdown and HTML'
);

-- HTML entities replaced (and HTML tags removed)
select is(
    format_group_description('{"name": "Test Group", "description": "Test&nbsp;with&nbsp;spaces &lt;tag&gt; &amp; &quot;quotes&quot;"}'::json)::jsonb,
    '{"name": "Test Group", "description": "Test with spaces & \"quotes\""}'::jsonb,
    'Should replace HTML entities and remove HTML tags'
);

-- Long descriptions truncated to 500 characters
select ok(
    length(format_group_description(jsonb_build_object('name', 'Test Group', 'description', repeat('a', 600))::json)->>'description') = 500,
    'Should truncate long descriptions to 500 characters'
);

-- Complex markdown document
select is(
    format_group_description('{"name": "Test Group", "description": "# Main Title\n\nThis is a **complex** document with:\n\n- [Links](https://example.com)\n- *Italic text*\n- `code snippets`\n- ~~strikethrough~~\n\n> A blockquote with **nested** _formatting_\n\n```python\ncode_block()\n```\n\nAnd @mentions plus #123 references."}'::json)::jsonb,
    '{"name": "Test Group", "description": "Main Title This is a complex document with: Links Italic text strikethrough A blockquote with nested formatting And @mentions plus #123 references."}'::jsonb,
    'Should handle complex markdown document'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;