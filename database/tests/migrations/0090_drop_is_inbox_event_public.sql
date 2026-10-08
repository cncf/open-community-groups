-- Tests dropping the inbox event visibility helper replaced by is_event_public.

-- ============================================================================
-- SETUP
-- ============================================================================

begin;
select plan(5);

-- ============================================================================
-- VARIABLES
-- ============================================================================

\set groupID '90000000-0000-0000-0000-000000000004'
\set privateConversationID '90000000-0000-0000-0000-000000000005'
\set publicConversationID '90000000-0000-0000-0000-000000000006'

-- ============================================================================
-- TESTS
-- ============================================================================

-- Should drop the replaced inbox event visibility helper
select hasnt_function('is_inbox_event_public', array['event', '"group"']::name[]);

-- Should flag the public event as public in the conversation thread
select is(
    inbox_conversation_json(:'publicConversationID'::uuid)::jsonb->'event'->'is_public',
    'true'::jsonb,
    'Should flag the public event as public in the conversation thread'
);

-- Should flag the public event as public in the conversations list
select is(
    (
        select conversation->'event'->'is_public'
        from jsonb_array_elements(
            search_inbox_conversations(:'groupID'::uuid, null, '{}'::jsonb)::jsonb->'conversations'
        ) conversation
        where conversation->>'inbox_conversation_id' = :'publicConversationID'
    ),
    'true'::jsonb,
    'Should flag the public event as public in the conversations list'
);

-- Should flag the unpublished event as not public in the conversation thread
select is(
    inbox_conversation_json(:'privateConversationID'::uuid)::jsonb->'event'->'is_public',
    'false'::jsonb,
    'Should flag the unpublished event as not public in the conversation thread'
);

-- Should flag the unpublished event as not public in the conversations list
select is(
    (
        select conversation->'event'->'is_public'
        from jsonb_array_elements(
            search_inbox_conversations(:'groupID'::uuid, null, '{}'::jsonb)::jsonb->'conversations'
        ) conversation
        where conversation->>'inbox_conversation_id' = :'privateConversationID'
    ),
    'false'::jsonb,
    'Should flag the unpublished event as not public in the conversations list'
);

-- ============================================================================
-- CLEANUP
-- ============================================================================

select * from finish();
rollback;
