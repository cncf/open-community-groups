-- Adds a reply on behalf of the group to one of its inbox conversations.
create or replace function add_inbox_group_reply(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_inbox_conversation_id uuid,
    p_body text
)
returns json as $$
declare
    v_conversation inbox_conversation;
    v_inbox_message_id uuid;
    v_now timestamptz;
begin
    -- Lock the conversation within the group
    v_conversation := lock_group_inbox_conversation(p_group_id, p_inbox_conversation_id);

    -- Capture the write time after taking the lock
    v_now := clock_timestamp();

    -- Reject replies to conversations whose user account was deleted
    if v_conversation.user_id is null then
        raise exception 'conversation is read-only' using errcode = 'OCG01';
    end if;

    -- Reject replies to conversations marked as spam, which must be unmarked first
    if v_conversation.inbox_conversation_status_id = 'spam' then
        raise exception 'conversation is marked as spam' using errcode = 'OCG01';
    end if;

    -- Store the reply
    v_inbox_message_id := append_inbox_message(
        v_conversation,
        p_actor_user_id,
        p_body,
        'group-reply',
        v_now
    );

    -- Record the audit row
    perform insert_inbox_conversation_audit(
        'inbox_reply_sent',
        p_actor_user_id,
        v_conversation,
        v_now
    );

    -- Return the posted identifiers
    return json_build_object(
        'group_id', p_group_id,
        'inbox_conversation_id', v_conversation.inbox_conversation_id,
        'inbox_message_id', v_inbox_message_id
    );
end;
$$ language plpgsql;
