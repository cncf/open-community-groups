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
    v_conversation inbox_conversation;
    v_last_message_kind text;
    v_now timestamptz;
    v_status text;
begin
    -- Lock the conversation within the group
    v_conversation := lock_group_inbox_conversation(p_group_id, p_inbox_conversation_id);

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

    -- Derive the status the latest message implies
    v_status := inbox_conversation_status_for_message_kind(v_last_message_kind);

    -- Restore the status without touching the activity time
    update inbox_conversation
    set inbox_conversation_status_id = v_status
    where inbox_conversation_id = p_inbox_conversation_id;

    -- Record the audit row
    perform insert_inbox_conversation_audit(
        'inbox_conversation_unmarked_as_spam',
        p_actor_user_id,
        v_conversation,
        v_now
    );
end;
$$ language plpgsql;
