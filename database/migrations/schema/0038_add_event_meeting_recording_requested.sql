-- Add organizer control for automatic event meeting recordings.

alter table event
    add column meeting_recording_requested boolean default true not null;
