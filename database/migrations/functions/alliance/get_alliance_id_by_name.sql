-- Returns the alliance ID for a alliance with the given name.
create or replace function get_alliance_id_by_name(p_name text)
returns uuid as $$
    select alliance_id
    from alliance
    where name = p_name
    and active = true;
$$ language sql;
