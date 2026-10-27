-- Appends a message without surrounding whitespace to a locked inbox
-- conversation and applies its status transition: group replies answer the
-- conversation and every other message opens it. The last message time never
-- moves backwards.
create or replace function append_inbox_message(
    p_conversation inbox_conversation,
    p_author_user_id uuid,
    p_body text,
    p_kind text,
    p_now timestamptz
)
returns uuid as $$
declare
    v_inbox_message_id uuid;
begin
    -- Store the message without surrounding whitespace
    insert into inbox_message (
        body,
        created_at,
        inbox_conversation_id,
        kind,

        author_user_id
    ) values (
        regexp_replace(p_body, '^\s+|\s+$', '', 'g'),
        p_now,
        p_conversation.inbox_conversation_id,
        p_kind,

        p_author_user_id
    )
    returning inbox_message_id into v_inbox_message_id;

    -- Persist the status the message implies and the latest activity time
    update inbox_conversation
    set
        inbox_conversation_status_id = inbox_conversation_status_for_message_kind(p_kind),
        last_message_at = greatest(last_message_at, p_now)
    where inbox_conversation_id = p_conversation.inbox_conversation_id;

    -- Return the stored message identifier
    return v_inbox_message_id;
end;
$$ language plpgsql;
