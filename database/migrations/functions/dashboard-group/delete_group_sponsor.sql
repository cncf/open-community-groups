-- Deletes a sponsor from the group.
create or replace function delete_group_sponsor(
    p_group_id uuid,
    p_group_sponsor_id uuid
)
returns void as $$
    delete from group_sponsor
    where group_sponsor_id = p_group_sponsor_id
    and group_id = p_group_id;
$$ language sql;
