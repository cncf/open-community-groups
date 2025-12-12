-- Add triggers to enforce cross-table events community/group integrity.
-- These triggers ensure that events hosts, speakers, and sponsors belong to
-- the same community/group as the event they are associated with.

-- Trigger function to validate event host belongs to the event's community.
create or replace function check_event_host_community()
returns trigger as $$
declare
    v_event_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get event's community
    select g.community_id into v_event_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = NEW.event_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_event_community_id then
        raise exception 'user not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on event_host INSERT/UPDATE
create trigger event_host_community_check
    before insert or update on event_host
    for each row
    execute function check_event_host_community();

-- Trigger function to validate event speaker belongs to the event's community.
create or replace function check_event_speaker_community()
returns trigger as $$
declare
    v_event_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get event's community
    select g.community_id into v_event_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = NEW.event_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_event_community_id then
        raise exception 'user not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on event_speaker INSERT/UPDATE
create trigger event_speaker_community_check
    before insert or update on event_speaker
    for each row
    execute function check_event_speaker_community();

-- Trigger function to validate session speaker belongs to the session's event's community.
create or replace function check_session_speaker_community()
returns trigger as $$
declare
    v_session_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get session's event's community
    select g.community_id into v_session_community_id
    from session s
    join event e using (event_id)
    join "group" g using (group_id)
    where s.session_id = NEW.session_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_session_community_id then
        raise exception 'user not found in community';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on session_speaker INSERT/UPDATE
create trigger session_speaker_community_check
    before insert or update on session_speaker
    for each row
    execute function check_session_speaker_community();

-- Trigger function to validate event sponsor belongs to the event's group.
create or replace function check_event_sponsor_group()
returns trigger as $$
declare
    v_event_group_id uuid;
    v_sponsor_group_id uuid;
begin
    -- Get event's group
    select group_id into v_event_group_id
    from event
    where event_id = NEW.event_id;

    -- Get sponsor's group
    select group_id into v_sponsor_group_id
    from group_sponsor
    where group_sponsor_id = NEW.group_sponsor_id;

    -- Validate groups match
    if v_sponsor_group_id is distinct from v_event_group_id then
        raise exception 'sponsor not found in group';
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on event_sponsor INSERT/UPDATE
create trigger event_sponsor_group_check
    before insert or update on event_sponsor
    for each row
    execute function check_event_sponsor_group();
