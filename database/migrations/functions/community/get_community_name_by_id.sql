-- Returns the community name for a community with the given ID.
create or replace function get_community_name_by_id(p_community_id uuid)
returns text as $$
    select name
    from community
    where community_id = p_community_id
    and active = true;
$$ language sql;
