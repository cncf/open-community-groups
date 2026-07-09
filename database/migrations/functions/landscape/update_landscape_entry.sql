create or replace function update_landscape_entry(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_entry_id uuid,
    p_input jsonb,
    p_tags text[],
    p_accelerator_tracks text[]
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

    if trim(p_input->>'kind') = 'accelerator' then
        insert into landscape_accelerator_profile (
            landscape_entry_id,
            application_url,
            curriculum_url,
            cohort_status,
            starts_on,
            ends_on,
            tracks,
            weekly_agenda,
            updated_at
        )
        values (
            p_entry_id,
            nullif(trim(p_input->>'accelerator_application_url'), ''),
            nullif(trim(p_input->>'accelerator_curriculum_url'), ''),
            nullif(trim(p_input->>'accelerator_cohort_status'), ''),
            nullif(trim(p_input->>'accelerator_starts_on'), '')::date,
            nullif(trim(p_input->>'accelerator_ends_on'), '')::date,
            coalesce(p_accelerator_tracks, '{}'::text[]),
            nullif(trim(p_input->>'accelerator_weekly_agenda'), '')::jsonb,
            current_timestamp
        )
        on conflict (landscape_entry_id) do update
        set application_url = excluded.application_url,
            curriculum_url = excluded.curriculum_url,
            cohort_status = excluded.cohort_status,
            starts_on = excluded.starts_on,
            ends_on = excluded.ends_on,
            tracks = excluded.tracks,
            weekly_agenda = excluded.weekly_agenda,
            updated_at = current_timestamp;
    else
        delete from landscape_accelerator_profile
        where landscape_entry_id = p_entry_id;
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
