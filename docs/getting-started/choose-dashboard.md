<!-- markdownlint-disable MD013 -->

# Choose Your Dashboard

OCG has three dashboards, each supporting a different kind of work: personal tasks (`User`),
community management (`Community`), and group or event management (`Group`).

## How to Pick the Right Workspace

Start with what you need to do, not the menu label. This matrix combines tasks, access, and
expected outcomes in one view:

| If you need to... | Use this dashboard | Who gets it | Core outcomes |
| --- | --- | --- | --- |
| Manage your profile, invitations, proposals, submissions, and your own audit history | [User Dashboard](/dashboard/user ':ignore') | Any logged-in user | Keep profile current, accept invitations, submit to CFS, review your actions |
| Manage community-wide identity, admins, taxonomy, analytics, groups, and community audit logs | [Community Dashboard](/dashboard/community ':ignore') | Community team members | Manage team access, branding, regions, categories, analytics, groups, and review community actions |
| Run events, organizers, members, sponsors, and group audit review | [Group Dashboard](/dashboard/group ':ignore') | Group team members | Deliver events, manage members, coordinate organizers and sponsors, and review group actions |

![Dashboard options from user menu](../screenshots/navigation-user-menu.png)

Guide deep-dives:

- [Public Site Guide](../guides/public-site.md)
- [User Dashboard Guide](../guides/user-dashboard.md)
- [Community Dashboard Guide](../guides/community-dashboard.md)
- [Group Dashboard Guide](../guides/group-dashboard.md)
- [Event Operations](../guides/event-operations.md)

## Access Model and Why It Matters

Dashboard visibility depends on your role. If a dashboard is missing from your menu, your account
does not currently have access to it.

The two organizer dashboards also depend on selected context:

- [Community Dashboard](/dashboard/community ':ignore') requires a selected community.
- [Group Dashboard](/dashboard/group ':ignore') requires both a selected community and a selected group.

If the right context is not selected yet, some organizer actions stay unavailable until you choose
the needed community or group.

!> Missing dashboard entries usually mean you either do not have access yet or have not selected
the right context.
Community Dashboard needs a selected community.
Group Dashboard needs both a selected community and a selected group.

## Fixed Role Model

OCG now uses fixed roles for community and group management. Roles are assigned per team member and
define what operations are allowed.

Community team roles:

| Role | What it can do |
| --- | --- |
| `admin` | Full community management (`settings`, `taxonomy`, `team`, `groups`) and group-level write operations in that community |
| `groups-manager` | Manage groups and group-level write operations in that community, without community settings/taxonomy/team control |
| `viewer` | Read-only access |

![Community roles](../screenshots/dashboard-community-team-roles.png)

Group team roles:

| Role | What it can do |
| --- | --- |
| `admin` | Full group management (`events`, `members`, `settings`, `sponsors`, `team`) |
| `events-manager` | Event operations only (`events`) |
| `viewer` | Read-only access |

![Group roles](../screenshots/dashboard-group-members-list-roles.png)

UI behavior:

- Controls are disabled when your role cannot perform an operation.
- Server-side authorization still enforces permissions even if a request is sent manually.

## If a Dashboard Is Missing

Use this order to unblock quickly:

1. Open [User Dashboard -> Invitations](/dashboard/user?tab=invitations ':ignore').
2. Accept pending community/group invitations.
3. Refresh the page (or sign out/in).
4. Re-open your avatar menu and check for new dashboard entries.

If visibility still does not update, use
[Troubleshooting](../support/troubleshooting.md).

![User invitations](../screenshots/dashboard-user-invitations.png)

## Typical Starting Paths

### Member or speaker path

Start in [User Dashboard](/dashboard/user ':ignore'), complete your profile, then create session proposals
only when you need to submit to event CFS.

Continue with [User Dashboard Guide](../guides/user-dashboard.md) and
[Public Site Guide](../guides/public-site.md).

### Community lead path

Start in [Community Dashboard](/dashboard/community?tab=settings ':ignore') to verify settings and team
membership first, then review [Regions](/dashboard/community?tab=regions ':ignore'),
[Group Categories](/dashboard/community?tab=group-categories ':ignore'), and
[Event Categories](/dashboard/community?tab=event-categories ':ignore'). Move to
[Groups](/dashboard/community?tab=groups ':ignore') after taxonomy and ownership structure are in place.
Use [Logs](/dashboard/community?tab=logs ':ignore') when you need a historical view of community dashboard activity.

Continue with [Community Dashboard Guide](../guides/community-dashboard.md).

### Group organizer path

Start in [Group Dashboard](/dashboard/group?tab=settings ':ignore') and move straight into
[Events](/dashboard/group?tab=events ':ignore'), because event setup, publishing, attendance, and
submissions are the operational center of group work. Use
[Logs](/dashboard/group?tab=logs ':ignore') when you need a historical view of group dashboard activity.

Continue with [Group Dashboard Guide](../guides/group-dashboard.md) and
[Event Operations](../guides/event-operations.md).
