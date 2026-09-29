-- Adds a follow-up message from a user to one of their inbox conversations,
-- reopening it when it was closed. Conversations marked as spam no longer
-- accept messages.
create or replace function add_inbox_user_message(
    p_actor_user_id uuid,
    p_inbox_conversation_id uuid,
    p_body text
)
returns json as $$
declare
    v_can_send_follow_up boolean;
    v_community_id uuid;
    v_conversation inbox_conversation;
    v_inbox_message_id uuid;
    v_now timestamptz;
    v_previous_status text;
begin
    -- Serialize this user's inbox writes so limits hold under concurrency
    perform 1
    from "user"
    where user_id = p_actor_user_id
    for no key update;

    -- Lock the user's conversation while its group still exists
    select ic.*
    into v_conversation
    from inbox_conversation ic
    join "group" g on g.group_id = ic.group_id
    where ic.inbox_conversation_id = p_inbox_conversation_id
    and ic.user_id = p_actor_user_id
    and g.deleted = false
    for update of ic;

    -- Reject conversations outside the user's scope
    if not found then
        raise exception 'conversation not found' using errcode = 'OCG01';
    end if;

    -- Reject conversations the group marked as spam
    if v_conversation.inbox_conversation_status_id = 'spam' then
        raise exception 'conversation no longer accepts messages' using errcode = 'OCG01';
    end if;

    -- Capture the write time after taking the locks
    v_now := clock_timestamp();

    -- Load the user's daily limits
    select l.can_send_follow_up
    into v_can_send_follow_up
    from inbox_user_rate_limits(p_actor_user_id, v_now) l;

    -- Reject users who reached the daily message limit
    if not v_can_send_follow_up then
        raise exception 'daily message limit reached' using errcode = 'OCG01';
    end if;

    -- Remember the status before the message changes it
    v_previous_status := v_conversation.inbox_conversation_status_id;

    -- Store the follow-up message
    v_inbox_message_id := append_inbox_message(
        v_conversation,
        p_actor_user_id,
        p_body,
        'user-reply',
        v_now
    );

    -- Resolve the community used by the audit rows
    select g.community_id
    into v_community_id
    from "group" g
    where g.group_id = v_conversation.group_id;

    -- Record the message audit row
    perform insert_audit_log(
        'inbox_message_sent',
        p_actor_user_id,
        'inbox_conversation',
        v_conversation.inbox_conversation_id,
        v_community_id,
        v_conversation.group_id,
        v_conversation.event_id,
        p_created_at => v_now
    );

    -- Record the reopening of a closed conversation
    if v_previous_status = 'closed' then
        perform insert_audit_log(
            'inbox_conversation_reopened',
            p_actor_user_id,
            'inbox_conversation',
            v_conversation.inbox_conversation_id,
            v_community_id,
            v_conversation.group_id,
            v_conversation.event_id,
            p_created_at => v_now
        );
    end if;

    -- Return the posted identifiers
    return json_build_object(
        'group_id', v_conversation.group_id,
        'inbox_conversation_id', v_conversation.inbox_conversation_id,
        'inbox_message_id', v_inbox_message_id
    );
end;
$$ language plpgsql;
