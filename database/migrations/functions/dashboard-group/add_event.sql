-- add_event adds a new event to the database.
create or replace function add_event(
    p_group_id uuid,
    p_event jsonb
)
returns uuid as $$
declare
    v_event_id uuid;
    v_community_id uuid;
    v_host_id uuid;
    v_session jsonb;
    v_session_id uuid;
    v_speaker_id uuid;
begin
    -- Get community_id for validation
    select community_id into v_community_id
    from "group"
    where group_id = p_group_id;

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
        meetup_url,
        photos_urls,
        recording_url,
        registration_required,
        starts_at,
        streaming_url,
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
        p_event->>'meetup_url',
        case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
        p_event->>'recording_url',
        (p_event->>'registration_required')::boolean,
        (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
        p_event->>'streaming_url',
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

    -- Insert event sponsors
    if p_event->'sponsors' is not null then
        insert into event_sponsor (
            event_id,
            name,
            logo_url,
            level,
            website_url
        )
        select
            v_event_id,
            sponsor->>'name',
            sponsor->>'logo_url',
            sponsor->>'level',
            sponsor->>'website_url'
        from jsonb_array_elements(p_event->'sponsors') as sponsor;
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
                recording_url,
                streaming_url
            ) values (
                v_event_id,
                v_session->>'name',
                v_session->>'description',
                (v_session->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
                (v_session->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
                v_session->>'kind',
                v_session->>'location',
                v_session->>'recording_url',
                v_session->>'streaming_url'
            )
            returning session_id into v_session_id;

            -- Insert speakers for this session
            if v_session->'speakers' is not null then
                for v_speaker_id in select (jsonb_array_elements_text(v_session->'speakers'))::uuid
                loop
                    -- Validate speaker exists in same community
                    if not exists (
                        select 1 from "user"
                        where user_id = v_speaker_id
                        and community_id = v_community_id
                    ) then
                        raise exception 'speaker user % not found in community', v_speaker_id;
                    end if;

                    insert into session_speaker (session_id, user_id)
                    values (v_session_id, v_speaker_id);
                end loop;
            end if;
        end loop;
    end if;

    return v_event_id;
end;
$$ language plpgsql;