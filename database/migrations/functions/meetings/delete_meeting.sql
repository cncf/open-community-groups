-- delete_meeting deletes a meeting and completes the event/session claim.
create or replace function delete_meeting(
    p_meeting_id uuid,
    p_event_id uuid,
    p_session_id uuid,
    p_sync_claimed_at timestamptz,
    p_sync_state_hash text
) returns void as $$
declare
    v_claim_held boolean := false;
begin
    -- Orphan meeting case: the claim lives on the meeting row itself
    if p_event_id is null and p_session_id is null then
        if p_meeting_id is not null then
            delete from meeting
            where meeting_id = p_meeting_id
              and sync_claimed_at = p_sync_claimed_at;
        end if;
        return;
    end if;

    -- Complete event or session claim when the worker still holds it
    v_claim_held := release_meeting_sync(
        p_event_id,
        p_session_id,
        p_sync_claimed_at,
        p_sync_state_hash,
        null
    );

    -- Delete meeting (if one exists) only when the worker still held the claim
    if v_claim_held and p_meeting_id is not null then
        delete from meeting where meeting_id = p_meeting_id;
    end if;
end;
$$ language plpgsql;
