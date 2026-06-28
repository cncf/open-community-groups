-- mark_stale_google_meet_recording_publish_claims_unknown releases abandoned
-- Google Meet recording publish claims.
create or replace function mark_stale_google_meet_recording_publish_claims_unknown(
    p_timeout_seconds bigint
) returns integer as $$
    with released as (
        update meeting
        set recording_publish_claimed_at = null,
            recording_publish_checked_at = current_timestamp,
            recording_publish_error = 'recording publish claim timed out',
            updated_at = current_timestamp
        where meeting_provider_id = 'google_meet'
          and recording_publish_claimed_at is not null
          and recording_publish_claimed_at <= current_timestamp - (p_timeout_seconds::text || ' seconds')::interval
        returning meeting_id
    )
    select count(*)::integer from released;
$$ language sql;
