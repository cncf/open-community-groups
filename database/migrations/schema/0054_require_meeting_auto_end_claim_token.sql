-- Require the auto-end claim token when releasing claims or recording outcomes

drop function if exists release_meeting_auto_end_check_claim(uuid);
drop function if exists set_meeting_auto_end_check_outcome(uuid, text);
