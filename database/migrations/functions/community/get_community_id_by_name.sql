-- Returns the community ID for a community with the given name.
create or replace function get_community_id_by_name(p_name text)
returns uuid as $$
    select community_id
    from community
    where name = p_name
    and active = true;
$$ language sql;
