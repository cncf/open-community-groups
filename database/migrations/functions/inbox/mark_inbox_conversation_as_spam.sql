-- Marks an inbox conversation of a group as spam. Marking an already marked
-- conversation succeeds without recording anything new.
create or replace function mark_inbox_conversation_as_spam(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_inbox_conversation_id uuid
)
returns void as $$
declare
    v_conversation inbox_conversation;
    v_now timestamptz;
begin
    -- Lock the conversation within the group
    v_conversation := lock_group_inbox_conversation(p_group_id, p_inbox_conversation_id);

    -- Capture the write time after taking the lock
    v_now := clock_timestamp();

    -- Keep conversations already marked as spam unchanged
    if v_conversation.inbox_conversation_status_id = 'spam' then
        return;
    end if;

    -- Mark the conversation as spam without touching its activity time
    update inbox_conversation
    set inbox_conversation_status_id = 'spam'
    where inbox_conversation_id = p_inbox_conversation_id;

    -- Record the audit row
    perform insert_inbox_conversation_audit(
        'inbox_conversation_marked_as_spam',
        p_actor_user_id,
        v_conversation,
        v_now
    );
end;
$$ language plpgsql;
