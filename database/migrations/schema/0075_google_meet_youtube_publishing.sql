alter table meeting
    add column if not exists recording_publish_claimed_at timestamptz,
    add column if not exists recording_publish_checked_at timestamptz,
    add column if not exists recording_publish_drive_file_id text,
    add column if not exists recording_publish_error text,
    add column if not exists recording_publish_url text;

alter table meeting
    drop constraint if exists meeting_recording_publish_drive_file_id_check,
    drop constraint if exists meeting_recording_publish_error_check,
    drop constraint if exists meeting_recording_publish_url_check,
    add constraint meeting_recording_publish_drive_file_id_check
        check (btrim(recording_publish_drive_file_id) <> ''),
    add constraint meeting_recording_publish_error_check
        check (btrim(recording_publish_error) <> ''),
    add constraint meeting_recording_publish_url_check
        check (btrim(recording_publish_url) <> '');

create index if not exists meeting_google_meet_recording_publish_pending_idx
    on meeting (recording_publish_checked_at, updated_at)
    where meeting_provider_id = 'google_meet'
      and recording_publish_url is null;
