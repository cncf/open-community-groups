-- add_event adds a new event to the database.
create or replace function add_event(
    p_group_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null
)
returns uuid as $$
declare
    v_cfs_label jsonb;
    v_ends_at timestamptz;
    v_event_id uuid;
    v_event_speaker jsonb;
    v_host_id uuid;
    v_max_retries int := 10;
    v_provider_max_participants int;
    v_retries int := 0;
    v_session jsonb;
    v_session_ends_at timestamptz;
    v_session_id uuid;
    v_session_speaker jsonb;
    v_session_starts_at timestamptz;
    v_slug text;
    v_speaker_featured boolean;
    v_speaker_id uuid;
    v_sponsor jsonb;
    v_sponsor_id uuid;
    v_sponsor_level text;
    v_starts_at timestamptz;
begin
    -- Validate event dates are not in the past
    if p_event->>'starts_at' is not null then
        v_starts_at := (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone');
        if v_starts_at < current_timestamp then
            raise exception 'event starts_at cannot be in the past';
        end if;
    end if;

    if p_event->>'ends_at' is not null then
        v_ends_at := (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone');
        if v_ends_at < current_timestamp then
            raise exception 'event ends_at cannot be in the past';
        end if;
    end if;

    -- Validate session dates are not in the past
    if p_event->'sessions' is not null then
        for v_session in select jsonb_array_elements(p_event->'sessions')
        loop
            v_session_starts_at := (v_session->>'starts_at')::timestamp at time zone (p_event->>'timezone');
            if v_session_starts_at < current_timestamp then
                raise exception 'session starts_at cannot be in the past';
            end if;

            if v_session->>'ends_at' is not null then
                v_session_ends_at := (v_session->>'ends_at')::timestamp at time zone (p_event->>'timezone');
                if v_session_ends_at < current_timestamp then
                    raise exception 'session ends_at cannot be in the past';
                end if;
            end if;
        end loop;
    end if;

    -- Validate event capacity against max_participants when meeting is requested
    if (p_event->>'meeting_requested')::boolean = true then
        v_provider_max_participants := (p_cfg_max_participants->>(p_event->>'meeting_provider_id'))::int;

        if v_provider_max_participants is not null
           and (p_event->>'capacity')::int > v_provider_max_participants
        then
            raise exception 'event capacity (%) exceeds maximum participants allowed (%)',
                (p_event->>'capacity')::int, v_provider_max_participants;
        end if;
    end if;

    -- Validate CFS labels payload
    if p_event->'cfs_labels' is not null then
        if jsonb_array_length(p_event->'cfs_labels') > 200 then
            raise exception 'too many cfs labels';
        end if;

        if exists (
            select 1
            from (
                select nullif(cfs_label->>'name', '') as cfs_label_name
                from jsonb_array_elements(p_event->'cfs_labels') as cfs_label
            ) cfs_labels
            where cfs_labels.cfs_label_name is not null
            group by cfs_labels.cfs_label_name
            having count(*) > 1
        ) then
            raise exception 'duplicate cfs label names';
        end if;
    end if;

    -- Insert event with unique slug generation and collision retry
    loop
        v_slug := generate_slug(7);

        begin
            insert into event (
                group_id,
                name,
                slug,
                description,
                timezone,
                event_category_id,
                event_kind_id,

                banner_mobile_url,
                banner_url,
                capacity,
                cfs_description,
                cfs_enabled,
                cfs_ends_at,
                cfs_starts_at,
                description_short,
                ends_at,
                event_reminder_enabled,
                location,
                logo_url,
                meeting_hosts,
                meeting_in_sync,
                meeting_join_url,
                meeting_provider_id,
                meeting_recording_url,
                meeting_requested,
                meetup_url,
                photos_urls,
                registration_required,
                starts_at,
                tags,
                venue_address,
                venue_city,
                venue_country_code,
                venue_country_name,
                venue_name,
                venue_state,
                venue_zip_code
            ) values (
                p_group_id,
                p_event->>'name',
                v_slug,
                p_event->>'description',
                p_event->>'timezone',
                (p_event->>'category_id')::uuid,
                p_event->>'kind_id',

                p_event->>'banner_mobile_url',
                p_event->>'banner_url',
                (p_event->>'capacity')::int,
                nullif(p_event->>'cfs_description', ''),
                (p_event->>'cfs_enabled')::boolean,
                (p_event->>'cfs_ends_at')::timestamp at time zone (p_event->>'timezone'),
                (p_event->>'cfs_starts_at')::timestamp at time zone (p_event->>'timezone'),
                p_event->>'description_short',
                (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
                coalesce((p_event->>'event_reminder_enabled')::boolean, true),
                case
                    when (p_event->>'latitude') is not null and (p_event->>'longitude') is not null
                    then ST_SetSRID(ST_MakePoint((p_event->>'longitude')::float, (p_event->>'latitude')::float), 4326)::geography
                    else null
                end,
                p_event->>'logo_url',
                case when p_event->'meeting_hosts' is not null then array(select jsonb_array_elements_text(p_event->'meeting_hosts')) else null end,
                case
                    when (p_event->>'meeting_requested')::boolean = true then false
                    else null
                end,
                p_event->>'meeting_join_url',
                p_event->>'meeting_provider_id',
                p_event->>'meeting_recording_url',
                (p_event->>'meeting_requested')::boolean,
                p_event->>'meetup_url',
                case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
                (p_event->>'registration_required')::boolean,
                (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
                case when p_event->'tags' is not null then array(select jsonb_array_elements_text(p_event->'tags')) else null end,
                p_event->>'venue_address',
                p_event->>'venue_city',
                p_event->>'venue_country_code',
                p_event->>'venue_country_name',
                p_event->>'venue_name',
                p_event->>'venue_state',
                p_event->>'venue_zip_code'
            )
            returning event_id into v_event_id;

            exit; -- Success, exit the loop
        exception when unique_violation then
            v_retries := v_retries + 1;
            if v_retries >= v_max_retries then
                raise exception 'failed to generate unique slug after % attempts', v_max_retries;
            end if;
        end;
    end loop;

    -- Insert CFS labels
    if p_event->'cfs_labels' is not null then
        for v_cfs_label in select jsonb_array_elements(p_event->'cfs_labels')
        loop
            insert into event_cfs_label (event_id, name, color)
            values (
                v_event_id,
                nullif(v_cfs_label->>'name', ''),
                v_cfs_label->>'color'
            );
        end loop;
    end if;

    -- Insert event hosts
    if p_event->'hosts' is not null then
        for v_host_id in select (jsonb_array_elements_text(p_event->'hosts'))::uuid
        loop
            insert into event_host (event_id, user_id)
            values (v_event_id, v_host_id);
        end loop;
    end if;

    -- Insert event speakers
    if p_event->'speakers' is not null then
        for v_event_speaker in select jsonb_array_elements(p_event->'speakers')
        loop
            -- Extract speaker details
            v_speaker_id := (v_event_speaker->>'user_id')::uuid;
            v_speaker_featured := (v_event_speaker->>'featured')::boolean;

            insert into event_speaker (event_id, user_id, featured)
            values (v_event_id, v_speaker_id, v_speaker_featured);
        end loop;
    end if;

    -- Insert event sponsors with per-event level
    if p_event->'sponsors' is not null then
        for v_sponsor in select jsonb_array_elements(p_event->'sponsors')
        loop
            -- Extract sponsor details
            v_sponsor_id := (v_sponsor->>'group_sponsor_id')::uuid;
            v_sponsor_level := v_sponsor->>'level';

            insert into event_sponsor (event_id, group_sponsor_id, level)
            values (v_event_id, v_sponsor_id, v_sponsor_level);
        end loop;
    end if;

    -- Insert sessions and speakers
    if p_event->'sessions' is not null then
        for v_session in select jsonb_array_elements(p_event->'sessions')
        loop
            -- Insert session
            insert into session (
                event_id,
                name,
                description,
                starts_at,
                ends_at,
                cfs_submission_id,
                session_kind_id,
                location,
                meeting_hosts,
                meeting_in_sync,
                meeting_join_url,
                meeting_provider_id,
                meeting_recording_url,
                meeting_requested
            ) values (
                v_event_id,
                v_session->>'name',
                v_session->>'description',
                (v_session->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
                (v_session->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
                nullif(v_session->>'cfs_submission_id', '')::uuid,
                v_session->>'kind',
                v_session->>'location',
                case when v_session->'meeting_hosts' is not null then array(select jsonb_array_elements_text(v_session->'meeting_hosts')) else null end,
                case
                    when (v_session->>'meeting_requested')::boolean = true then false
                    else null
                end,
                v_session->>'meeting_join_url',
                v_session->>'meeting_provider_id',
                v_session->>'meeting_recording_url',
                (v_session->>'meeting_requested')::boolean
            )
            returning session_id into v_session_id;

            -- Insert speakers for this session
            if v_session->'speakers' is not null then
                for v_session_speaker in select jsonb_array_elements(v_session->'speakers')
                loop
                    -- Extract speaker details
                    v_speaker_id := (v_session_speaker->>'user_id')::uuid;
                    v_speaker_featured := (v_session_speaker->>'featured')::boolean;

                    insert into session_speaker (session_id, user_id, featured)
                    values (v_session_id, v_speaker_id, v_speaker_featured);
                end loop;
            end if;
        end loop;
    end if;

    return v_event_id;
end;
$$ language plpgsql;
