-- add_event adds a new event to the database.
create or replace function add_event(
    p_group_id uuid,
    p_event jsonb,
    p_cfg_max_participants jsonb default null
)
returns uuid as $$
declare
    v_event_id uuid;
    v_community_id uuid;
    v_event_speaker jsonb;
    v_host_id uuid;
    v_provider_max_participants int;
    v_session jsonb;
    v_session_id uuid;
    v_session_speaker jsonb;
    v_speaker_id uuid;
    v_speaker_featured boolean;
    v_sponsor jsonb;
    v_sponsor_id uuid;
    v_sponsor_level text;
begin
    -- Get community_id for validation
    select community_id into v_community_id
    from "group"
    where group_id = p_group_id;

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

    -- Insert event
    insert into event (
        group_id,
        name,
        slug,
        description,
        timezone,
        event_category_id,
        event_kind_id,

        banner_url,
        capacity,
        description_short,
        ends_at,
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
        venue_name,
        venue_zip_code
    ) values (
        p_group_id,
        p_event->>'name',
        p_event->>'slug',
        p_event->>'description',
        p_event->>'timezone',
        (p_event->>'category_id')::uuid,
        p_event->>'kind_id',

        p_event->>'banner_url',
        (p_event->>'capacity')::int,
        p_event->>'description_short',
        (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
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
        p_event->>'venue_name',
        p_event->>'venue_zip_code'
    )
    returning event_id into v_event_id;

    -- Insert event hosts
    if p_event->'hosts' is not null then
        for v_host_id in select (jsonb_array_elements_text(p_event->'hosts'))::uuid
        loop
            -- Validate host exists in same community
            if not exists (
                select 1 from "user"
                where user_id = v_host_id
                and community_id = v_community_id
            ) then
                raise exception 'host user % not found in community', v_host_id;
            end if;

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

            -- Validate speaker exists in same community
            if not exists (
                select 1 from "user"
                where user_id = v_speaker_id
                and community_id = v_community_id
            ) then
                raise exception 'speaker user % not found in community', v_speaker_id;
            end if;

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

            -- Validate sponsor belongs to the group
            if not exists (
                select 1 from group_sponsor
                where group_sponsor_id = v_sponsor_id
                and group_id = p_group_id
            ) then
                raise exception 'sponsor % not found in group', v_sponsor_id;
            end if;

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

                    -- Validate speaker exists in same community
                    if not exists (
                        select 1 from "user"
                        where user_id = v_speaker_id
                        and community_id = v_community_id
                    ) then
                        raise exception 'speaker user % not found in community', v_speaker_id;
                    end if;

                    insert into session_speaker (session_id, user_id, featured)
                    values (v_session_id, v_speaker_id, v_speaker_featured);
                end loop;
            end if;
        end loop;
    end if;

    return v_event_id;
end;
$$ language plpgsql;
