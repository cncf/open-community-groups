-- Returns the number of open inbox conversations of a group.
create or replace function count_group_open_inbox_conversations(p_group_id uuid)
returns int as $$
    select count(*)::int
    from inbox_conversation ic
    where ic.group_id = p_group_id
    and ic.inbox_conversation_status_id = 'open';
$$ language sql stable;
