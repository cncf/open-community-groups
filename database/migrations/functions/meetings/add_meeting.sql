-- add_meeting adds a new meeting and completes the event/session claim.
drop function if exists add_meeting(text, text, text, text, text, uuid, uuid);
create or replace function add_meeting(
    p_meeting_provider_id text,
    p_provider_meeting_id text,
    p_provider_host_user_id text,
    p_url text,
    p_password text,
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text
) returns void as $$
begin
    -- Insert new meeting
    insert into meeting (
        meeting_provider_id,
        provider_meeting_id,
        provider_host_user_id,
        join_url,
        password,
        event_id,
        session_id
    )
    values (
        p_meeting_provider_id,
        p_provider_meeting_id,
        p_provider_host_user_id,
        p_url,
        p_password,
        p_event_id,
        p_session_id
    );

    -- Complete event claim when the owner state did not change
    if p_event_id is not null then
        update event
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then null
                else meeting_error
            end,
            meeting_in_sync = current_state.sync_state_hash = p_sync_state_hash,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        from (
            select get_event_meeting_sync_state_hash(p_event_id) as sync_state_hash
        ) current_state
        where event_id = p_event_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    end if;

    -- Complete session claim when the owner state did not change
    if p_session_id is not null then
        update session
        set
            meeting_error = case
                when current_state.sync_state_hash = p_sync_state_hash then null
                else meeting_error
            end,
            meeting_in_sync = current_state.sync_state_hash = p_sync_state_hash,
            meeting_provider_host_user = null,
            meeting_sync_claimed_at = null
        from (
            select get_session_meeting_sync_state_hash(p_session_id) as sync_state_hash
        ) current_state
        where session_id = p_session_id
          and meeting_sync_claimed_at = p_sync_claimed_at;
    end if;
end;
$$ language plpgsql;
