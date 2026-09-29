-- Returns an inbox conversation thread of a user, or null when the user does
-- not own the conversation or its group was deleted.
create or replace function get_user_inbox_conversation(
    p_user_id uuid,
    p_inbox_conversation_id uuid
)
returns json as $$
    select inbox_conversation_json(ic.inbox_conversation_id)
    from inbox_conversation ic
    join "group" g on g.group_id = ic.group_id
    where ic.inbox_conversation_id = p_inbox_conversation_id
    and ic.user_id = p_user_id
    and g.deleted = false;
$$ language sql stable;
