create or replace function delete_landscape_entry(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_entry_id uuid
) returns void language plpgsql as $$
begin
    delete from landscape_entry
    where landscape_entry_id = p_entry_id
      and alliance_id = p_alliance_id;

    if not found then
        raise exception 'landscape entry not found';
    end if;

    perform insert_audit_log(
        'landscape_entry_deleted',
        p_actor_user_id,
        'landscape_entry',
        p_entry_id,
        p_alliance_id,
        null
    );
end;
$$;
