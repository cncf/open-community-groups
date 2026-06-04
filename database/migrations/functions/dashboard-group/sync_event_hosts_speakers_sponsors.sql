-- sync_event_hosts_speakers_sponsors synchronizes an event's hosts, speakers, and sponsors.
create or replace function sync_event_hosts_speakers_sponsors(
    p_event_id uuid,
    p_event jsonb
)
returns void as $$
begin
    -- Replace associations from the payload
    delete from event_host where event_id = p_event_id;
    delete from event_speaker where event_id = p_event_id;
    delete from event_sponsor where event_id = p_event_id;

    if p_event->'hosts' is not null then
        insert into event_host (event_id, user_id)
        select p_event_id, host.user_id::uuid
        from jsonb_array_elements_text(p_event->'hosts') as host(user_id);
    end if;

    if p_event->'speakers' is not null then
        insert into event_speaker (event_id, user_id, featured)
        select p_event_id, speaker.user_id, speaker.featured
        from jsonb_to_recordset(p_event->'speakers') as speaker(featured boolean, user_id uuid);
    end if;

    if p_event->'sponsors' is not null then
        insert into event_sponsor (event_id, group_sponsor_id, level)
        select p_event_id, sponsor.group_sponsor_id, sponsor.level
        from jsonb_to_recordset(p_event->'sponsors') as sponsor(group_sponsor_id uuid, level text);
    end if;
end;
$$ language plpgsql;
