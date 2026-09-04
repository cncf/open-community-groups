-- add_meeting adds a new meeting and completes the event/session claim.
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
declare
    v_claim_held boolean := false;
begin
    -- Complete event or session claim when the worker still holds it
    v_claim_held := release_meeting_sync(
        p_event_id,
        p_session_id,
        p_sync_claimed_at,
        p_sync_state_hash,
        null
    );

    -- Insert new meeting only when the worker still held the claim
    if v_claim_held then
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
    end if;
end;
$$ language plpgsql;
