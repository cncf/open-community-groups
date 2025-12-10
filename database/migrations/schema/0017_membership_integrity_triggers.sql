-- Add triggers to enforce cross-table community integrity for membership tables
-- and category/region references. These triggers ensure that users, categories,
-- and regions belong to the same community as the entities they are associated
-- with.

-- =============================================================================
-- MEMBERSHIP TRIGGERS
-- =============================================================================

-- Trigger function to validate group member belongs to the group's community.
create or replace function check_group_member_community()
returns trigger as $$
declare
    v_group_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get group's community
    select community_id into v_group_community_id
    from "group"
    where group_id = NEW.group_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_group_community_id then
        raise exception 'member user % not found in community', NEW.user_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on group_member INSERT/UPDATE
create trigger group_member_community_check
    before insert or update on group_member
    for each row
    execute function check_group_member_community();

-- Trigger function to validate event attendee belongs to the event's community.
create or replace function check_event_attendee_community()
returns trigger as $$
declare
    v_event_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get event's community
    select g.community_id into v_event_community_id
    from event e
    join "group" g using (group_id)
    where e.event_id = NEW.event_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_event_community_id then
        raise exception 'attendee user % not found in community', NEW.user_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on event_attendee INSERT/UPDATE
create trigger event_attendee_community_check
    before insert or update on event_attendee
    for each row
    execute function check_event_attendee_community();

-- Trigger function to validate group team member belongs to the group's community.
create or replace function check_group_team_community()
returns trigger as $$
declare
    v_group_community_id uuid;
    v_user_community_id uuid;
begin
    -- Get group's community
    select community_id into v_group_community_id
    from "group"
    where group_id = NEW.group_id;

    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from v_group_community_id then
        raise exception 'team member user % not found in community', NEW.user_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on group_team INSERT/UPDATE
create trigger group_team_community_check
    before insert or update on group_team
    for each row
    execute function check_group_team_community();

-- Trigger function to validate community team member belongs to the community.
create or replace function check_community_team_community()
returns trigger as $$
declare
    v_user_community_id uuid;
begin
    -- Get user's community
    select community_id into v_user_community_id
    from "user"
    where user_id = NEW.user_id;

    -- Validate communities match
    if v_user_community_id is distinct from NEW.community_id then
        raise exception 'team member user % not found in community', NEW.user_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on community_team INSERT/UPDATE
create trigger community_team_community_check
    before insert or update on community_team
    for each row
    execute function check_community_team_community();

-- =============================================================================
-- CATEGORY/REGION TRIGGERS
-- =============================================================================

-- Trigger function to validate event category belongs to the event's community.
create or replace function check_event_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
    v_group_community_id uuid;
begin
    -- Get event's group community
    select community_id into v_group_community_id
    from "group"
    where group_id = NEW.group_id;

    -- Get category's community
    select community_id into v_category_community_id
    from event_category
    where event_category_id = NEW.event_category_id;

    -- Validate communities match
    if v_category_community_id is distinct from v_group_community_id then
        raise exception 'event category % not found in community', NEW.event_category_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on event INSERT/UPDATE
create trigger event_category_community_check
    before insert or update on event
    for each row
    execute function check_event_category_community();

-- Trigger function to validate group category belongs to the group's community.
create or replace function check_group_category_community()
returns trigger as $$
declare
    v_category_community_id uuid;
begin
    -- Get category's community
    select community_id into v_category_community_id
    from group_category
    where group_category_id = NEW.group_category_id;

    -- Validate communities match
    if v_category_community_id is distinct from NEW.community_id then
        raise exception 'group category % not found in community', NEW.group_category_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on group INSERT/UPDATE
create trigger group_category_community_check
    before insert or update on "group"
    for each row
    execute function check_group_category_community();

-- Trigger function to validate region belongs to the group's community.
create or replace function check_group_region_community()
returns trigger as $$
declare
    v_region_community_id uuid;
begin
    -- Skip validation if region_id is null
    if NEW.region_id is null then
        return NEW;
    end if;

    -- Get region's community
    select community_id into v_region_community_id
    from region
    where region_id = NEW.region_id;

    -- Validate communities match
    if v_region_community_id is distinct from NEW.community_id then
        raise exception 'region % not found in community', NEW.region_id;
    end if;

    return NEW;
end;
$$ language plpgsql;

-- Trigger on group INSERT/UPDATE
create trigger group_region_community_check
    before insert or update on "group"
    for each row
    execute function check_group_region_community();
