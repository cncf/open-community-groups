-- Closes an inbox conversation of a group. Closing an already closed
-- conversation succeeds without recording anything new, and conversations
-- marked as spam are rejected.
create or replace function close_inbox_conversation(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_inbox_conversation_id uuid
)
returns void as $$
declare
    v_community_id uuid;
    v_conversation inbox_conversation;
    v_now timestamptz;
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

    -- Capture the write time after taking the lock
    v_now := clock_timestamp();

    -- Keep already closed conversations unchanged
    if v_conversation.inbox_conversation_status_id = 'closed' then
        return;
    end if;

    -- Reject conversations marked as spam, which must be unmarked first
    if v_conversation.inbox_conversation_status_id = 'spam' then
        raise exception 'conversation is marked as spam' using errcode = 'OCG01';
    end if;

    -- Close the conversation without touching its activity time
    update inbox_conversation
    set inbox_conversation_status_id = 'closed'
    where inbox_conversation_id = p_inbox_conversation_id;

    -- Resolve the community used by the audit row
    select g.community_id
    into v_community_id
    from "group" g
    where g.group_id = p_group_id;

    -- Record the audit row
    perform insert_audit_log(
        'inbox_conversation_closed',
        p_actor_user_id,
        'inbox_conversation',
        p_inbox_conversation_id,
        v_community_id,
        p_group_id,
        v_conversation.event_id,
        p_created_at => v_now
    );
end;
$$ language plpgsql;
