-- update_meeting updates a meeting and completes the event/session claim.
create or replace function update_meeting(
    p_meeting_id uuid,
    p_provider_meeting_id text,
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

    -- Update meeting only when the worker still held the claim
    if v_claim_held then
        update meeting
        set provider_meeting_id = p_provider_meeting_id,
            join_url = p_url,
            password = p_password,
            updated_at = current_timestamp
        where meeting_id = p_meeting_id;
    end if;
end;
$$ language plpgsql;
