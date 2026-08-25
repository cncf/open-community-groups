-- Adds attendee credentials and check-in management permissions.

-- Give every attendee a unique check-in credential.
alter table event_attendee
add column check_in_code uuid default gen_random_uuid() not null;

-- Enforce credential uniqueness across attendees.
create unique index event_attendee_check_in_code_idx
    on event_attendee (check_in_code);

-- Rotates a credential whenever canceled or incomplete attendance is confirmed.
create function rotate_event_attendee_check_in_code()
returns trigger as $$
begin
    -- Revoke the previous credential on a fresh confirmation
    if new.status = 'confirmed' and old.status <> 'confirmed' then
        new.check_in_code := gen_random_uuid();
    end if;

    -- Continue the attendee update with the current credential
    return new;
end;
$$ language plpgsql;

-- Apply credential rotation to attendance status changes.
create trigger event_attendee_check_in_code_rotation
before update of status on event_attendee
for each row execute function rotate_event_attendee_check_in_code();

-- Add a group role for delegated check-in management.
insert into group_role (group_role_id, display_name)
values ('check-in-manager', 'Check-In Manager');

-- Add the group-scoped check-in management permission.
insert into group_permission (group_permission_id, display_name)
values ('group.check-ins.write', 'Check-Ins Write');

-- Grant check-in management to community roles that manage groups.
insert into community_role_group_permission (community_role_id, group_permission_id)
values
    ('admin', 'group.check-ins.write'),
    ('groups-manager', 'group.check-ins.write');

-- Grant check-in management and visibility to the applicable group roles.
insert into group_role_group_permission (group_role_id, group_permission_id)
values
    ('admin', 'group.check-ins.write'),
    ('check-in-manager', 'group.check-ins.write'),
    ('check-in-manager', 'group.read'),
    ('events-manager', 'group.check-ins.write');

-- Remove check-in function signatures superseded by the credential flow.
drop function if exists check_in_event(uuid, uuid, uuid, boolean);
drop function if exists is_event_check_in_window_open(uuid, uuid);
drop function if exists manual_check_in_event(uuid, uuid, uuid, uuid);
