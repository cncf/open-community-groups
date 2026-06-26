<!-- markdownlint-disable MD013 -->

# Alliance Dashboard Guide

Use the Alliance Dashboard to manage alliance-wide settings and operations:
identity, governance, taxonomy, team access, analytics, and groups.

If you are deciding workspace scope first, read
[Choose Your Dashboard](../getting-started/choose-dashboard.md).

Path: [/dashboard/alliance](/dashboard/alliance ':ignore')

**Sections:**

- [What This Dashboard Owns](#what-this-dashboard-owns)
- [Access and Context](#access-and-context)
- [Creating and Managing Multiple Alliances](#creating-and-managing-multiple-alliances)
- [Roles and Permissions](#roles-and-permissions)
- [Settings: Alliance Identity](#settings-alliance-identity)
- [Team: Alliance Access](#team-alliance-access)
- [Regions: Geographic Scope](#regions-geographic-scope)
- [Group Categories: Group Taxonomy](#group-categories-group-taxonomy)
- [Event Categories: Event Taxonomy](#event-categories-event-taxonomy)
- [Analytics: Momentum](#analytics-momentum)
- [Groups: Portfolio](#groups-portfolio)
- [Audit: Logs](#audit-logs)
- [Recommended Cadence](#recommended-cadence)

## What This Dashboard Owns

Use the alliance scope to manage the structure shared by all groups. You are
not running one event here; you are shaping how the whole alliance is
presented and managed.

Main areas:

- [Settings](/dashboard/alliance?tab=settings ':ignore'): alliance identity, branding, social presence,
  and long-form content.
- [Team](/dashboard/alliance?tab=team ':ignore'): alliance-level admins and invitation flow.
- [Regions](/dashboard/alliance?tab=regions ':ignore'): alliance geography model for group classification.
- [Group Categories](/dashboard/alliance?tab=group-categories ':ignore'): reusable taxonomy for groups.
- [Event Categories](/dashboard/alliance?tab=event-categories ':ignore'): reusable taxonomy for events.
- [Analytics](/dashboard/alliance?tab=analytics ':ignore'): alliance growth trends and volume metrics.
- [Groups](/dashboard/alliance?tab=groups ':ignore'): group creation, maintenance, activation state,
  and lifecycle transitions.
- [Logs](/dashboard/alliance?tab=logs ':ignore'): read-only audit trail for alliance dashboard actions.

![Alliance dashboard analytics](../screenshots/dashboard-alliance-analytics.png)

## Access and Context

You are ready to work in this dashboard when:

1. You are logged in.
2. Your account is on the alliance team.
3. A alliance is selected in dashboard context.

If no alliance is selected yet, some actions stay unavailable until you choose one.

For invitation acceptance and dashboard access, see
[User Dashboard Guide](user-dashboard.md).

## Creating and Managing Multiple Alliances

Multiple alliances are supported. Use this when GOUP needs separate public identities, teams,
groups, categories, regions, and brand pages for different communities.

Only platform admins can create a new alliance.

### Make a User a Platform Admin

Platform admin is a user-level flag in the database. On a Docker deployment, connect to the
Postgres container and update the user:

```bash
docker exec -it goup-postgis psql -U postgres
```

Then in `psql`:

```sql
\c ocg
update "user"
set platform_admin = true
where username = 'your-username';

select username, platform_admin
from "user"
where username = 'your-username';
```

The result should show `platform_admin` as `t`. Sign out and sign back in so the dashboard reloads
the user permissions.

### Create the Alliance

After signing in as a platform admin:

1. Open [Alliance Dashboard](/dashboard/alliance ':ignore').
2. Select `Create Alliance` from the sidebar.
3. Fill the alliance basics and submit.

The direct dashboard tab is:

```text
/dashboard/alliance?tab=create-alliance
```

The create form loads from:

```text
/dashboard/alliance/create
```

### Where the New Alliance Appears

After creation, the new alliance appears in the Alliance Dashboard context selector/list. Use the
selector to switch between alliances before managing settings, groups, taxonomy, team access, or
analytics.

Publicly, an alliance is available at its slug path:

```text
/{alliance-name}
```

For example:

```text
/goup
```

### First Setup Checklist

For each new alliance, configure these before inviting many users:

1. `Settings`: display name, description, logo, banner, social links, and brand content.
2. `Team`: add at least one accepted alliance `admin`.
3. `Regions`: add the geography values groups will use.
4. `Group Categories`: add the categories shown in group setup and Explore filters.
5. `Event Categories`: add the event taxonomy organizers will use.
6. `Groups`: create or import the first active groups.

!> Keep at least one accepted alliance admin per alliance. The app blocks removing or demoting the
final accepted admin.

## Roles and Permissions

Alliance role permissions are fixed and enforced by middleware plus database checks:

| Alliance role   | Alliance read | Groups    | Settings  | Taxonomy  | Team      |
| ---------------- | -------------- | --------- | --------- | --------- | --------- |
| `admin`          | Yes            | Write     | Write     | Write     | Write     |
| `groups-manager` | Yes            | Write     | Read only | Read only | Read only |
| `viewer`         | Yes            | Read only | Read only | Read only | Read only |

![Alliance roles](../screenshots/dashboard-alliance-team-roles.png)

Alliance role impact on group-level operations in the same alliance:

- `admin` and `groups-manager` can perform group write operations (`events`, `members`,
  `settings`, `sponsors`, `team`) without needing group-team role assignment.
- If `Restrict group team management` is enabled in alliance settings, group team management
  (`team`) is limited to alliance `admin` and `groups-manager` roles.
- `viewer` keeps read-only visibility.

UI behavior:

- When your role cannot perform an action, controls are disabled.
- Server-side authorization blocks unauthorized requests.

![Alliance disabled form](../screenshots/dashboard-alliance-permissions-role.png)

## Settings: Alliance Identity

`Settings` is where you shape how the alliance appears publicly and how organizers enrich it over
time.

Key sections include:

- General Settings.
- Branding.
- Social Links.
- Advertisement.
- Additional Content.

Common use cases:

- Keeping display name and description up to date.
- Restricting group team management to alliance admins and groups managers when policy requires it.
- Maintaining logo, banner, and Open Graph preview assets for consistent presentation.
- Managing social links, optional ad placements, gallery images, tags, and extra links.

Advertisement settings are alliance-wide. When a banner image is configured, OCG shows it on the
public alliance page and as a floating banner on public group and event pages for that alliance.
The optional banner link URL makes the banner clickable.

Field requirements, character limits, and list limits are shown inline in the settings UI.

![Alliance settings area](../screenshots/dashboard-alliance-settings.png)

## Team: Alliance Access

Use `Team` to invite members with a alliance role, update existing roles, or remove members.

Current assignable roles:

- `admin`
- `groups-manager`
- `viewer`

Safety rules:

- OCG blocks removing the final accepted alliance admin.
- OCG blocks demoting the final accepted alliance admin to a non-admin role.

!> The final accepted alliance admin cannot be removed or demoted.
Add another accepted member first, then retry removal.

Pending states are visible (`Invitation sent`) so you can tell the difference between invited and
fully active collaborators.

When you add a team member, OCG sends an invitation with a direct link to
[User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').

![Alliance team area](../screenshots/dashboard-alliance-team.png)

## Regions: Geographic Scope

`Regions` is the alliance-level geography list used by groups.

You can:

- Add regions.
- Rename existing regions.
- Delete retired regions.

Operational rules:

- Region names must be unique within the selected alliance.
- Deletion is blocked when one or more groups still use that region.
- The table shows a `Groups` count to make dependencies visible before cleanup.

Where this appears downstream:

- Group setup/edit forms select region values from this list.
- Public discovery and filtering can use region as a search dimension.

![Alliance dashboard regions](../screenshots/dashboard-alliance-regions.png)

## Group Categories: Group Taxonomy

`Group Categories` defines reusable category values for all groups in the selected alliance.

You can:

- Add group categories.
- Rename existing categories.
- Delete unused categories.

Operational rules:

- Group category names must be unique within the selected alliance.
- Deletion is blocked when one or more groups still use that category.
- The table shows a `Groups` count per category for dependency checks.

Where this appears downstream:

- Group setup/edit forms select category values from this list.
- Public discovery and filtering can use group category as a search dimension.

![Alliance dashboard group categories](../screenshots/dashboard-alliance-group-categories.png)

## Event Categories: Event Taxonomy

`Event Categories` defines reusable category values for events across the selected alliance.

You can:

- Add event categories.
- Rename existing categories.
- Delete unused categories.

Operational rules:

- Event category names must be unique within the selected alliance.
- Deletion is blocked when one or more events still use that category.
- The table shows an `Events` count per category for dependency checks.

Where this appears downstream:

- Event editor (`Details` tab) uses this list for event categorization.
- Public event discovery and filtering can use event category.

![Alliance dashboard event categories](../screenshots/dashboard-alliance-event-categories.png)

## Analytics: Momentum

Alliance analytics shows totals and trends for:

- Groups.
- Members.
- Events.
- Attendees.
- Page views for the alliance page, all group pages, and all event pages.

Each metric is available as total, running total, and monthly values. This helps you spot
steady progress and notice unusual jumps with better context.

The `Page views` tab starts with total alliance, group, and event page views, then breaks
views down by page type with daily charts for the last month.

Analytics data is cached and may lag for a few minutes.

![Alliance dashboard analytics](../screenshots/dashboard-alliance-analytics.png)

## Groups: Portfolio

`Groups` is where alliance leads create and maintain the collection of groups under the
alliance umbrella.

Group records rely on taxonomy values from alliance-level `Regions` and `Group Categories`.

You can:

- Search groups.
- Add or update groups.
- Activate/deactivate groups.
- Delete retired groups.
- Open a group in [Group Dashboard](/dashboard/group ':ignore') for deeper operational work.

For execution workflows inside a specific group, continue with
[Group Dashboard Guide](group-dashboard.md).

Activity states:

- `Active`: group is available for normal public participation.
- `Inactive`: group is paused and can be reactivated later.

![Alliance groups area](../screenshots/dashboard-alliance-groups.png)

When creating a new group, `Add Group` starts with the basics first. Then you can add branding,
location, links, and optional content before launch.

Group-branding inheritance from this flow:

- If group logo is empty, the public group view uses the alliance logo.
- If group banner/mobile banner is empty, the public group view uses the alliance banner.

![Add group flow](../screenshots/dashboard-alliance-add-group.png)

### Group Lifecycle

- `Activate` restores visibility and operational flow.
- `Deactivate` pauses activity while preserving metadata.

## Audit: Logs

`AUDIT -> Logs` is the last section in the left dashboard menu. It gives alliance leads a
read-only activity stream for alliance dashboard operations.

Coverage in this view includes:

- Alliance settings updates.
- Alliance team membership changes, including invitation accept and reject outcomes.
- Region, group category, and event category changes.
- Group portfolio actions done from the alliance dashboard, including add, activate, deactivate,
  delete, and update.

Table behavior:

- Rows are ordered by newest first by default.
- You can filter by `Action`, `Actor`, and date range.
- You can switch ordering between newest first and oldest first.
- Pagination keeps the active filters applied.
- `Details` opens a popover when an audit row has extra metadata.

Target display behavior:

- OCG shows the resource type plus the current resource name.
- If the current resource row no longer exists, the audit row still remains and falls back to the
  name snapshot stored with the entry when available, or to the stored resource identifier.

Scope note:

- This screen is alliance-dashboard focused.
- Some overlapping actions, such as `group_updated`, can also appear in the group dashboard audit
  view when they match that dashboard's accepted scope.
- `Delete` is permanent retirement for groups that should no longer exist operationally.

When a group is inactive, its public-view shortcut is disabled in the groups table.

![Alliance groups actions](../screenshots/dashboard-alliance-groups-actions.png)

## Recommended Cadence

?> Use a recurring monthly or biweekly rhythm so identity, access, and group structure stay healthy.

1. Review [Settings](/dashboard/alliance?tab=settings ':ignore') monthly for brand accuracy.
2. Keep [Team](/dashboard/alliance?tab=team ':ignore') membership current to avoid operational
   bottlenecks.
3. Review [Regions](/dashboard/alliance?tab=regions ':ignore') so geography labels stay clean and useful.
4. Review [Group Categories](/dashboard/alliance?tab=group-categories ':ignore') to avoid stale taxonomy.
5. Review [Event Categories](/dashboard/alliance?tab=event-categories ':ignore') as event programs evolve.
6. Check [Analytics](/dashboard/alliance?tab=analytics ':ignore') on a regular cadence for trend shifts.
7. Use [Groups](/dashboard/alliance?tab=groups ':ignore') to retire stale structures and support active
   ones.

For event lifecycle operations after handoff to group teams, see
[Event Operations](event-operations.md).
