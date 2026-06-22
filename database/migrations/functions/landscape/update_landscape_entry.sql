create or replace function update_landscape_entry(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_entry_id uuid,
    p_input jsonb,
    p_tags text[]
) returns void language plpgsql as $$
begin
    update landscape_entry
    set name = trim(p_input->>'name'),
        kind = trim(p_input->>'kind'),
        summary = trim(p_input->>'summary'),
        description = nullif(trim(p_input->>'description'), ''),
        website_url = nullif(trim(p_input->>'website_url'), ''),
        github_url = nullif(trim(p_input->>'github_url'), ''),
        logo_url = nullif(trim(p_input->>'logo_url'), ''),
        category = nullif(trim(p_input->>'category'), ''),
        tags = coalesce(p_tags, '{}'::text[]),
        updated_at = current_timestamp
    where landscape_entry_id = p_entry_id
      and alliance_id = p_alliance_id;

    if not found then
        raise exception 'landscape entry not found';
    end if;

    perform insert_audit_log(
        'landscape_entry_updated',
        p_actor_user_id,
        'landscape_entry',
        p_entry_id,
        p_alliance_id,
        null
    );
end;
$$;
