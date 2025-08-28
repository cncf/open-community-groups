-- update_event updates an existing event in the database.
create or replace function update_event(
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb
)
returns void as $$
declare
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

    -- Update event
    update event set
        name = p_event->>'name',
        slug = p_event->>'slug',
        description = p_event->>'description',
        timezone = p_event->>'timezone',
        event_category_id = (p_event->>'category_id')::uuid,
        event_kind_id = p_event->>'kind_id',

        banner_url = p_event->>'banner_url',
        capacity = (p_event->>'capacity')::int,
        description_short = p_event->>'description_short',
        ends_at = (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
        logo_url = p_event->>'logo_url',
        meetup_url = p_event->>'meetup_url',
        photos_urls = case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
        recording_url = p_event->>'recording_url',
        registration_required = (p_event->>'registration_required')::boolean,
        starts_at = (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
        streaming_url = p_event->>'streaming_url',
        tags = case when p_event->'tags' is not null then array(select jsonb_array_elements_text(p_event->'tags')) else null end,
        venue_address = p_event->>'venue_address',
        venue_city = p_event->>'venue_city',
        venue_name = p_event->>'venue_name',
        venue_zip_code = p_event->>'venue_zip_code'
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    if not found then
        raise exception 'event not found';
    end if;

    -- Delete existing hosts, sponsors, sessions and speakers
    delete from event_host where event_id = p_event_id;
    delete from event_sponsor where event_id = p_event_id;
    delete from session_speaker where session_id in (
        select session_id from session where event_id = p_event_id
    );
    delete from session where event_id = p_event_id;

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
            values (p_event_id, v_host_id);
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
            p_event_id,
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
                p_event_id,
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
end;
$$ language plpgsql;