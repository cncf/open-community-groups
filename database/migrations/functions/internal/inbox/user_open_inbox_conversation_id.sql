-- Returns the most recently active open conversation of a user with a group
-- about an event, or null when there is none.
create or replace function user_open_inbox_conversation_id(
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns uuid as $$
    select ic.inbox_conversation_id
    from inbox_conversation ic
    where ic.event_id = p_event_id
    and ic.group_id = p_group_id
    and ic.user_id = p_user_id
    and ic.inbox_conversation_status_id = 'open'
    order by ic.last_message_at desc, ic.inbox_conversation_id desc
    limit 1;
$$ language sql stable;
