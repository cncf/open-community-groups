alter table landscape_entry
drop constraint if exists landscape_entry_kind_check;

alter table landscape_entry
add constraint landscape_entry_kind_check
check (kind in ('startup', 'github_project', 'partner_community', 'podcast_lead'));
