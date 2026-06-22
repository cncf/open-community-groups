create or replace function update_landscape_entry_published(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_entry_id uuid,
    p_published boolean
) returns void language plpgsql as $$
begin
    update landscape_entry
    set published = p_published,
        updated_at = current_timestamp
    where landscape_entry_id = p_entry_id
      and alliance_id = p_alliance_id;

    if not found then
        raise exception 'landscape entry not found';
    end if;

    perform insert_audit_log(
        case when p_published then 'landscape_entry_published' else 'landscape_entry_unpublished' end,
        p_actor_user_id,
        'landscape_entry',
        p_entry_id,
        p_alliance_id,
        null
    );
end;
$$;
