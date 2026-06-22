-- Returns the alliance name for a alliance with the given ID.
create or replace function get_alliance_name_by_id(p_alliance_id uuid)
returns text as $$
    select name
    from alliance
    where alliance_id = p_alliance_id
    and active = true;
$$ language sql;
