-- delete_group performs a soft delete by setting deleted=true and deleted_at timestamp.
create or replace function delete_group(
    p_group_id uuid
)
returns void as $$
begin
    update "group" set
        active = false,
        deleted = true,
        deleted_at = current_timestamp
    where group_id = p_group_id
    and deleted = false;

    if not found then
        raise exception 'group not found';
    end if;
end;
$$ language plpgsql;
