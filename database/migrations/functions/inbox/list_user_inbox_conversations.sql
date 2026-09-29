-- Returns a filtered page of the inbox conversations of a user.
create or replace function list_user_inbox_conversations(p_user_id uuid, p_filters jsonb)
returns json as $$
    select search_inbox_conversations(null, p_user_id, p_filters);
$$ language sql stable;
