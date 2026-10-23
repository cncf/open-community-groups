-- Locks an inbox conversation of a group and returns its row.
create or replace function lock_group_inbox_conversation(
    p_group_id uuid,
    p_inbox_conversation_id uuid
)
returns inbox_conversation as $$
declare
    v_conversation inbox_conversation;
begin
    -- Lock the conversation within the group
    select ic.*
    into v_conversation
    from inbox_conversation ic
    where ic.inbox_conversation_id = p_inbox_conversation_id
    and ic.group_id = p_group_id
    for update of ic;

    -- Reject conversations outside the group
    if not found then
        raise exception 'conversation not found' using errcode = 'OCG01';
    end if;

    -- Return the locked conversation row
    return v_conversation;
end;
$$ language plpgsql;
