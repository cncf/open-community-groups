create or replace function landscape_entry_json(p_entry landscape_entry)
returns jsonb language sql stable as $$
    select jsonb_build_object(
        'landscape_entry_id', p_entry.landscape_entry_id,
        'alliance_id', p_entry.alliance_id,
        'added_by_user_id', p_entry.added_by_user_id,
        'name', p_entry.name,
        'slug', p_entry.slug,
        'kind', p_entry.kind,
        'summary', p_entry.summary,
        'description', p_entry.description,
        'website_url', p_entry.website_url,
        'github_url', p_entry.github_url,
        'logo_url', p_entry.logo_url,
        'category', p_entry.category,
        'tags', p_entry.tags,
        'published', p_entry.published,
        'created_at', extract(epoch from p_entry.created_at)::bigint,
        'updated_at', extract(epoch from p_entry.updated_at)::bigint,
        'accelerator', (
            select case
                when lap.landscape_entry_id is null then null
                else jsonb_build_object(
                    'application_url', lap.application_url,
                    'curriculum_url', lap.curriculum_url,
                    'cohort_status', lap.cohort_status,
                    'starts_on', lap.starts_on,
                    'ends_on', lap.ends_on,
                    'tracks', lap.tracks,
                    'weekly_agenda', lap.weekly_agenda,
                    'updated_at', extract(epoch from lap.updated_at)::bigint
                )
            end
            from landscape_accelerator_profile lap
            where lap.landscape_entry_id = p_entry.landscape_entry_id
        )
    );
$$;
