-- Returns the conversation status a message of the given kind implies: group
-- replies answer it, every other message opens it.
create or replace function inbox_conversation_status_for_message_kind(p_kind text)
returns text as $$
    select case when p_kind = 'group-reply' then 'answered' else 'open' end;
$$ language sql immutable;
