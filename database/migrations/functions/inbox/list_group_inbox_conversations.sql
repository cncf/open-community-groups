-- Returns a filtered page of the inbox conversations of a group.
create or replace function list_group_inbox_conversations(p_group_id uuid, p_filters jsonb)
returns json as $$
    select search_inbox_conversations(p_group_id, null, p_filters);
$$ language sql stable;
