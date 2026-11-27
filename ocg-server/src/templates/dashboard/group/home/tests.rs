use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
};

use askama::Template;
use axum_messages::{Level, Message};
use uuid::Uuid;

use crate::{
    templates::{PageId, auth::UserMenuState, dashboard::group::sponsors},
    test_util::{element_html_with, opening_tag_with},
    types::{
        dashboard::group::home::UserGroupsByCommunity,
        pagination::NavigationLinks,
        tests::{sample_community_summary, sample_group_minimal, sample_site_settings},
    },
};

use super::{Content, Page};

#[test]
fn test_page_renders_group_shell_overrides_messages_and_modals() {
    // Setup the group dashboard page with a flash message
    let community_id = Uuid::from_u128(1);
    let group_id = Uuid::from_u128(2);
    let page = Page {
        can_manage_badges: false,
        can_manage_check_ins: false,
        can_manage_inbox: false,
        content: Content::Sponsors(sponsors::ListPage {
            can_manage_sponsors: false,
            navigation_links: NavigationLinks::default(),
            sponsors: vec![],
            total: 0,

            offset: None,
        }),
        groups_by_community: vec![UserGroupsByCommunity {
            community: sample_community_summary(community_id),
            groups: vec![sample_group_minimal(group_id)],
        }],
        inbox_open_count: 0,
        is_check_in_fallback: false,
        is_inbox_fallback: false,
        messages: vec![Message {
            level: Level::Success,
            message: "Sponsor saved.".to_string(),
            metadata: None,
        }],
        page_id: PageId::GroupDashboard,
        path: "/dashboard/group".into(),
        payments_ready: false,
        selected_community_id: community_id,
        selected_group_id: group_id,
        site_settings: sample_site_settings(),
        user: UserMenuState::default(),
    };

    // Render the page
    let html = page.render().unwrap();

    // Check the group shell overrides menu HTMX attributes and spinner classes
    let menu = opening_tag_with(&html, r#"id="dashboard-menu""#);
    assert!(menu.contains(r##"hx-target="#dashboard-layout""##));
    assert!(menu.contains(r##"hx-select="#dashboard-layout""##));
    assert!(menu.contains(r##"hx-select-oob="#mobile-dashboard-view:outerHTML""##));
    assert!(menu.contains(r#"hx-swap="outerHTML show:window:top""#));

    let spinner = opening_tag_with(&html, r#"id="dashboard-spinner""#);
    assert!(spinner.contains(r#"class="hx-spinner -mt-0.5 relative""#));

    // Check shared scripts, shell selectors, active tab script, flash messages, and group modals render
    assert!(html.contains("Group Dashboard"));
    assert!(html.contains("/static/js/common/tooltip-panel"));
    assert!(html.contains("/static/js/dashboard/confirm-actions"));
    assert!(html.contains("/static/js/dashboard/menu-drawer"));
    assert!(html.contains("/static/js/dashboard/community/community-selector"));
    assert!(html.contains("/static/js/dashboard/group/group-selector"));
    assert!(html.contains("/static/js/dashboard/group/tab-modules"));
    assert!(html.contains("/static/js/dashboard/group/sponsors"));

    // Check unrelated group tab scripts are not loaded eagerly in the shell
    for unrelated_script in [
        "/static/js/dashboard/group/attendees",
        "/static/js/dashboard/group/badges",
        "/static/js/dashboard/group/check-in/scanner",
        "/static/js/dashboard/group/cohosts",
        "/static/js/dashboard/group/event-add",
        "/static/js/dashboard/group/event-update",
        "/static/js/dashboard/group/events-list",
        "/static/js/dashboard/group/members",
        "/static/js/dashboard/group/refunds",
        "/static/js/dashboard/group/settings-form",
    ] {
        assert!(
            !html.contains(unrelated_script),
            "unexpected eager script in sponsors tab render: {unrelated_script}"
        );
    }

    let main = element_html_with(&html, r#"id="dashboard-main-content""#);
    assert!(main.contains("Sponsor saved."));
    assert!(main.contains("<user-info-modal></user-info-modal>"));
    assert!(main.contains("<badge-award-modal></badge-award-modal>"));
}

#[test]
fn test_group_dashboard_partial_scripts_match_tab_modules_manifest() {
    // Parse MODULE_GROUP_LOADERS entries from tab-modules.js
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let tab_modules_source =
        fs::read_to_string(manifest_dir.join("static/js/dashboard/group/tab-modules.js")).unwrap();
    let loader_groups = parse_tab_module_loader_groups(&tab_modules_source);

    // Verify every group dashboard partial's script tags match its loader group entry
    let partial_to_group = [
        ("dashboard/audit_logs.html", "audit-logs"),
        ("dashboard/group/attendees_list.html", "attendees"),
        ("dashboard/group/badges.html", "badges"),
        ("dashboard/group/badges_artwork.html", "badges-artwork"),
        ("dashboard/group/badges_awards.html", "badges"),
        ("dashboard/group/check_in_list.html", "check-in"),
        ("dashboard/group/cohosts_list.html", "cohosts"),
        (
            "dashboard/group/event_submissions_list.html",
            "event-submissions",
        ),
        ("dashboard/group/events_add.html", "event-add"),
        ("dashboard/group/events_list.html", "events-list"),
        ("dashboard/group/events_update.html", "event-update"),
        (
            "dashboard/group/invitation_requests_list.html",
            "event-requests",
        ),
        ("dashboard/group/members_list.html", "members"),
        ("dashboard/group/refunds_list.html", "refunds"),
        ("dashboard/group/settings_update.html", "settings"),
        ("dashboard/group/sponsors_add.html", "sponsor-form"),
        ("dashboard/group/sponsors_list.html", "sponsors-list"),
        ("dashboard/group/sponsors_update.html", "sponsor-form"),
        ("dashboard/group/surveys_responses.html", "survey-responses"),
        ("dashboard/group/team_list.html", "team"),
        ("dashboard/group/waitlist_list.html", "event-requests"),
        ("dashboard/inbox_conversation.html", "inbox"),
        ("dashboard/inbox_list.html", "inbox"),
    ];

    let mut covered_groups = BTreeSet::new();
    for (template_rel, group_key) in partial_to_group {
        covered_groups.insert(group_key.to_string());
        let template_source =
            fs::read_to_string(manifest_dir.join("templates").join(template_rel)).unwrap();
        let template_scripts = extract_module_script_srcs(&template_source);
        let loader_scripts = loader_groups
            .get(group_key)
            .unwrap_or_else(|| panic!("missing loader group '{group_key}' for {template_rel}"));
        assert_eq!(
            &template_scripts, loader_scripts,
            "module script mismatch between {template_rel} and tab-modules.js group '{group_key}'"
        );
    }

    // Verify every entry in MODULE_GROUP_LOADERS is accounted for above
    let manifest_groups: BTreeSet<String> = loader_groups.keys().cloned().collect();
    assert_eq!(manifest_groups, covered_groups);
}

/// Extracts all `<script type="module" src="/static/js/...">` URLs from a template.
fn extract_module_script_srcs(template: &str) -> BTreeSet<String> {
    let mut srcs = BTreeSet::new();
    let mut rest = template;
    while let Some(pos) = rest.find("<script") {
        let after_open = &rest[pos..];
        let Some(tag_end) = after_open.find('>') else {
            break;
        };
        let tag = &after_open[..=tag_end];
        if tag.contains(r#"type="module""#)
            && let Some(src_start) = tag.find(r#"src=""#)
        {
            let after_src = &tag[src_start + 5..];
            if let Some(src_end) = after_src.find('"') {
                srcs.insert(after_src[..src_end].to_string());
            }
        }
        rest = &after_open[tag_end + 1..];
    }
    srcs
}

/// Parses `MODULE_GROUP_LOADERS` keys and their `import("...")` targets from `tab-modules.js`.
fn parse_tab_module_loader_groups(source: &str) -> BTreeMap<String, BTreeSet<String>> {
    let start = source
        .find("const MODULE_GROUP_LOADERS = {")
        .expect("MODULE_GROUP_LOADERS definition exists");
    let body = &source[start..];
    let end = body.find("\n};").expect("MODULE_GROUP_LOADERS closing brace exists");
    let block = &body[..end];

    let mut groups: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut current_group: Option<String> = None;

    for line in block.lines().skip(1) {
        let trimmed = line.trim();
        if let Some((raw_key, _)) = trimmed.split_once(": () =>") {
            let key = raw_key.trim().trim_matches('"').to_string();
            groups.entry(key.clone()).or_default();
            current_group = Some(key);
        }
        if let Some(group_key) = &current_group {
            let mut rest = trimmed;
            while let Some(import_pos) = rest.find(r#"import(""#) {
                let after_import = &rest[import_pos + 8..];
                if let Some(quote_end) = after_import.find('"') {
                    groups
                        .get_mut(group_key)
                        .unwrap()
                        .insert(after_import[..quote_end].to_string());
                    rest = &after_import[quote_end + 1..];
                } else {
                    break;
                }
            }
        }
    }

    groups
}
