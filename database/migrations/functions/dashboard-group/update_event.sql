-- update_event updates an existing event in the database.
create or replace function update_event(
    p_group_id uuid,
    p_event_id uuid,
    p_event jsonb
)
returns void as $$
declare
    v_community_id uuid;
    v_event_speaker jsonb;
    v_host_id uuid;
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

    -- Update event
    update event set
        name = p_event->>'name',
        slug = p_event->>'slug',
        description = p_event->>'description',
        timezone = p_event->>'timezone',
        event_category_id = (p_event->>'category_id')::uuid,
        event_kind_id = p_event->>'kind_id',

        banner_url = nullif(p_event->>'banner_url', ''),
        capacity = (p_event->>'capacity')::int,
        description_short = nullif(p_event->>'description_short', ''),
        ends_at = (p_event->>'ends_at')::timestamp at time zone (p_event->>'timezone'),
        logo_url = nullif(p_event->>'logo_url', ''),
        meetup_url = nullif(p_event->>'meetup_url', ''),
        photos_urls = case when p_event->'photos_urls' is not null then array(select jsonb_array_elements_text(p_event->'photos_urls')) else null end,
        recording_url = nullif(p_event->>'recording_url', ''),
        registration_required = (p_event->>'registration_required')::boolean,
        starts_at = (p_event->>'starts_at')::timestamp at time zone (p_event->>'timezone'),
        streaming_url = nullif(p_event->>'streaming_url', ''),
        tags = case when p_event->'tags' is not null then array(select jsonb_array_elements_text(p_event->'tags')) else null end,
        venue_address = nullif(p_event->>'venue_address', ''),
        venue_city = nullif(p_event->>'venue_city', ''),
        venue_name = nullif(p_event->>'venue_name', ''),
        venue_zip_code = nullif(p_event->>'venue_zip_code', '')
    where event_id = p_event_id
    and group_id = p_group_id
    and deleted = false
    and canceled = false;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Delete existing hosts, sponsors, sessions and speakers
    delete from event_host where event_id = p_event_id;
    delete from event_speaker where event_id = p_event_id;
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
            values (p_event_id, v_speaker_id, v_speaker_featured);
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
            values (p_event_id, v_sponsor_id, v_sponsor_level);
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
end;
$$ language plpgsql;
