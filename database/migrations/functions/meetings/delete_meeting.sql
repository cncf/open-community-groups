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
        -- Delete the orphan meeting only when the worker still holds the claim
        if p_meeting_id is not null then
            delete from meeting
            where meeting_id = p_meeting_id
              and sync_claimed_at = p_sync_claimed_at;
        end if;

        -- Finish early because orphan meetings have no owning event or session
        return;
    end if;

    -- Complete event or session claim when the worker still holds it, leaving
    -- create tracking intact until a persisted meeting row is actually removed
    v_claim_held := release_meeting_sync(
        p_event_id,
        p_session_id,
        p_sync_claimed_at,
        p_sync_state_hash,
        null,
        false
    );

    -- Delete the owned meeting only when the worker still held the claim
    if v_claim_held and p_meeting_id is not null then
        delete from meeting
        where meeting_id = p_meeting_id
          and (
              (p_event_id is not null and event_id = p_event_id)
              or (p_session_id is not null and session_id = p_session_id)
          );

        -- Clear create tracking only when a persisted meeting row was actually removed
        if found then
            -- Clear event create tracking
            if p_event_id is not null then
                update event
                set
                    meeting_create_attempted_at = null,
                    meeting_last_provider_host_user = null
                where event_id = p_event_id;

            -- Clear session create tracking
            elsif p_session_id is not null then
                update session
                set
                    meeting_create_attempted_at = null,
                    meeting_last_provider_host_user = null
                where session_id = p_session_id;
            end if;
        end if;
    end if;
end;
$$ language plpgsql;
