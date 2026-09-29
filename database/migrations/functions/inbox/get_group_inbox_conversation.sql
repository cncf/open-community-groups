-- Returns an inbox conversation thread of a group, or null when the
-- conversation belongs to another group.
create or replace function get_group_inbox_conversation(
    p_group_id uuid,
    p_inbox_conversation_id uuid
)
returns json as $$
    select inbox_conversation_json(ic.inbox_conversation_id)
    from inbox_conversation ic
    where ic.inbox_conversation_id = p_inbox_conversation_id
    and ic.group_id = p_group_id;
$$ language sql stable;
