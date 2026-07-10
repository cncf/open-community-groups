-- Requires auto-end claim tokens when releasing claims or recording outcomes.

-- Drop signatures that do not require the claim timestamp
drop function if exists release_meeting_auto_end_check_claim(uuid);
drop function if exists set_meeting_auto_end_check_outcome(uuid, text);
