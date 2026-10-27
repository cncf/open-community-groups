-- Records an audit row for an inbox conversation, scoped to its group's
-- community, the group and the event.
create or replace function insert_inbox_conversation_audit(
    p_action text,
    p_actor_user_id uuid,
    p_conversation inbox_conversation,
    p_created_at timestamptz
)
returns void as $$
begin
    -- Record the audit row, deriving the community from the group
    perform insert_audit_log(
        p_action,
        p_actor_user_id,
        'inbox_conversation',
        p_conversation.inbox_conversation_id,
        p_group_id => p_conversation.group_id,
        p_event_id => p_conversation.event_id,
        p_created_at => p_created_at
    );
end;
$$ language plpgsql;
