-- Starts an inbox conversation between a user and the group that owns an
-- event. Returns the posted identifiers, or an open-conversation conflict when
-- the user already has an open conversation with that group. Users blocked by
-- spam reports are rejected.
create or replace function start_inbox_conversation(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_body text
)
returns json as $$
declare
    v_can_start_conversation boolean;
    v_conversation inbox_conversation;
    v_event_id uuid;
    v_group_id uuid;
    v_inbox_message_id uuid;
    v_now timestamptz;
begin
    -- Serialize this user's inbox writes so limits and conflicts hold under concurrency
    perform 1
    from "user"
    where user_id = p_actor_user_id
    for no key update;

    -- Capture the write time after taking the lock
    v_now := clock_timestamp();

    -- Resolve the event and the group that owns it
    select
        r.event_id,
        r.group_id
    into
        v_event_id,
        v_group_id
    from resolve_inbox_contact_event(p_community_id, p_event_id) r;

    -- Reject events that do not accept contact
    if not found then
        raise exception 'event not found' using errcode = 'OCG01';
    end if;

    -- Reject group team members contacting their own group
    if user_is_group_team_member(v_group_id, p_actor_user_id) then
        raise exception 'group team members cannot contact their own group' using errcode = 'OCG01';
    end if;

    -- Point the user to the open conversation they already have with the group
    if exists (
        select 1
        from inbox_conversation ic
        where ic.group_id = v_group_id
        and ic.user_id = p_actor_user_id
        and ic.inbox_conversation_status_id = 'open'
    ) then
        return json_build_object('conflict', 'open-conversation');
    end if;

    -- Reject users blocked by spam reports
    if is_inbox_user_blocked(v_group_id, p_actor_user_id) then
        raise exception 'you can no longer contact this group' using errcode = 'OCG01';
    end if;

    -- Load the user's daily limits
    select l.can_start_conversation
    into v_can_start_conversation
    from inbox_user_rate_limits(p_actor_user_id, v_now) l;

    -- Reject users who reached the daily limit of new conversations
    if not v_can_start_conversation then
        raise exception 'daily limit of new conversations reached' using errcode = 'OCG01';
    end if;

    -- Create the conversation
    insert into inbox_conversation (
        created_at,
        group_id,
        last_message_at,

        event_id,
        user_id
    ) values (
        v_now,
        v_group_id,
        v_now,

        v_event_id,
        p_actor_user_id
    )
    returning * into v_conversation;

    -- Store the first message
    v_inbox_message_id := append_inbox_message(
        v_conversation,
        p_actor_user_id,
        p_body,
        'initial',
        v_now
    );

    -- Record the audit row
    perform insert_audit_log(
        'inbox_conversation_started',
        p_actor_user_id,
        'inbox_conversation',
        v_conversation.inbox_conversation_id,
        p_community_id,
        v_group_id,
        v_event_id,
        p_created_at => v_now
    );

    -- Return the posted identifiers
    return json_build_object(
        'group_id', v_group_id,
        'inbox_conversation_id', v_conversation.inbox_conversation_id,
        'inbox_message_id', v_inbox_message_id
    );
end;
$$ language plpgsql;
