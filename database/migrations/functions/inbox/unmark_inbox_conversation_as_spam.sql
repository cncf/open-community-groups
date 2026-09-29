-- Unmarks an inbox conversation of a group as spam, restoring the status its
-- latest message implies: answered after a group reply, open otherwise.
-- Unmarking a conversation that is not marked as spam succeeds without
-- recording anything new.
create or replace function unmark_inbox_conversation_as_spam(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_inbox_conversation_id uuid
)
returns void as $$
declare
    v_community_id uuid;
    v_conversation inbox_conversation;
    v_last_message_kind text;
    v_now timestamptz;
    v_status text;
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

    -- Keep conversations not marked as spam unchanged
    if v_conversation.inbox_conversation_status_id <> 'spam' then
        return;
    end if;

    -- Load the kind of the latest message
    select m.kind
    into v_last_message_kind
    from inbox_message m
    where m.inbox_conversation_id = p_inbox_conversation_id
    order by m.created_at desc, m.inbox_message_id desc
    limit 1;

    -- Answer the conversation when the group wrote last
    if v_last_message_kind = 'group-reply' then
        v_status := 'answered';

    -- Open the conversation when the user wrote last
    else
        v_status := 'open';
    end if;

    -- Restore the status without touching the activity time
    update inbox_conversation
    set inbox_conversation_status_id = v_status
    where inbox_conversation_id = p_inbox_conversation_id;

    -- Resolve the community used by the audit row
    select g.community_id
    into v_community_id
    from "group" g
    where g.group_id = p_group_id;

    -- Record the audit row
    perform insert_audit_log(
        'inbox_conversation_unmarked_as_spam',
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
