-- Returns whether a user can no longer contact a group because the group
-- marked one of their conversations as spam, or because at least three groups
-- of the same community did. Unmarking a conversation lifts its report.
create or replace function is_inbox_user_blocked(p_group_id uuid, p_user_id uuid)
returns boolean as $$
    with
        -- Groups of the community that marked conversations of the user as spam
        reporting_groups as (
            select distinct ic.group_id
            from inbox_conversation ic
            join "group" rg on rg.group_id = ic.group_id
            join "group" g on g.community_id = rg.community_id
            where g.group_id = p_group_id
            and ic.user_id = p_user_id
            and ic.inbox_conversation_status_id = 'spam'
        )
    select
        exists (select 1 from reporting_groups r where r.group_id = p_group_id)
        or (select count(*) from reporting_groups) >= 3;
$$ language sql stable;
