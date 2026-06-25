//! Templates and types for group store management.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::validation::{
    MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_L, MAX_LEN_M, image_url_opt, trimmed_non_empty,
    trimmed_non_empty_opt,
};

/// Group dashboard store management page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/store_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage store items.
    pub can_manage_store: bool,
    /// Store items for the selected group.
    pub items: Vec<GroupStoreItem>,
}

/// Dashboard form payload for creating or updating a store item.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct StoreItemInput {
    /// Item name.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub name: String,
    /// Short item description.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub description: Option<String>,
    /// Optional product image URL.
    #[garde(custom(image_url_opt))]
    pub image_url: Option<String>,
    /// Price in minor units, for example cents.
    #[garde(range(min = 0))]
    pub price_minor: i64,
    /// ISO currency code.
    #[garde(pattern(r"^[A-Z]{3}$"))]
    pub currency_code: String,
    /// Optional available inventory count.
    #[garde(range(min = 0))]
    pub inventory_count: Option<i32>,
    /// External checkout URL where buyers purchase the item.
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty))]
    pub checkout_url: String,
    /// Whether the item should be emphasized.
    #[serde(default)]
    #[garde(skip)]
    pub featured: bool,
    /// Whether the item is visible in the group store.
    #[serde(default = "default_active")]
    #[garde(skip)]
    pub active: bool,
}

/// Store item shown in dashboards and public group stores.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupStoreItem {
    /// Store item identifier.
    pub group_store_item_id: Uuid,
    /// Group identifier.
    pub group_id: Uuid,
    /// Creating user identifier.
    pub created_by: Uuid,
    /// Item name.
    pub name: String,
    /// Item description.
    pub description: Option<String>,
    /// Item image URL.
    pub image_url: Option<String>,
    /// Price in minor units.
    pub price_minor: i64,
    /// Currency code.
    pub currency_code: String,
    /// Optional available inventory count.
    pub inventory_count: Option<i32>,
    /// External checkout URL.
    pub checkout_url: String,
    /// Whether the item is emphasized.
    pub featured: bool,
    /// Whether the item is visible.
    pub active: bool,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,
}

impl GroupStoreItem {
    /// Returns the display price using a simple minor-unit formatter.
    pub(crate) fn display_price(&self) -> String {
        let major = self.price_minor / 100;
        let minor = self.price_minor % 100;
        format!("{major}.{minor:02} {}", self.currency_code)
    }

    /// Returns whether the item should be treated as sold out.
    pub(crate) fn is_sold_out(&self) -> bool {
        self.inventory_count == Some(0)
    }

    /// Returns the inventory value for dashboard form inputs.
    pub(crate) fn inventory_input_value(&self) -> String {
        self.inventory_count
            .map(|count| count.to_string())
            .unwrap_or_default()
    }
}

fn default_active() -> bool {
    true
}
