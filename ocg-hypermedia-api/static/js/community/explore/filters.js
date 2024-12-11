// Filters
const COLLAPSIBLE_FILTERS = ["region", "distance"];

// Format date to ISO format (YYYY-MM-DD)
const formatDate = (date) => {
  return date.toISOString().split("T")[0];
};

// Open mobile filters
export const openFilters = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.remove("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.remove("hidden");
};

// Close mobile filters
export const closeFilters = () => {
  const drawer = document.getElementById("drawer-filters");
  drawer.classList.add("-translate-x-full");
  const backdrop = document.getElementById("drawer-backdrop");
  backdrop.classList.add("hidden");
};

// Reset filters
export const resetFilters = (formName) => {
  const form = document.getElementById(formName);
  document
    .querySelectorAll(`#${formName} input[type=checkbox]`)
    .forEach((el) => (el.checked = false));
  document
    .querySelectorAll(`#${formName} input[type=radio]`)
    .forEach((el) => (el.checked = false));
  document
    .querySelectorAll(`#${formName} input[value='']`)
    .forEach((el) => (el.checked = true));
  document.querySelector("input[name=date_from]").value = formatDate(
    new Date()
  );
  const aYearFromNow = new Date();
  aYearFromNow.setFullYear(aYearFromNow.getFullYear() + 1);
  document.querySelector("input[name=date_to]").value =
    formatDate(aYearFromNow);
  document
    .querySelectorAll(`#${formName} input[type=date]`)
    .forEach((el) => (el.value = ""));
  document.querySelector('input[name="ts_query"]').value = "";

  triggerChangeOnForm(form.id);
};

// Update any value and trigger change on form
export const updateAnyValue = (name, triggerChange) => {
  const anyInput = document.getElementById(`any-${name}`);
  if (!anyInput.isChecked) {
    const inputs = document.querySelectorAll(`input[name='${name}']:checked`);
    inputs.forEach((input) => {
      input.checked = false;
    });
    anyInput.checked = true;
    if (triggerChange) {
      const form = anyInput.closest("form");
      triggerChangeOnForm(form.id);
    }
  }
};

// Clean input field and trigger change on form
export const cleanInputField = (id, formId) => {
  const input = document.getElementById(id);
  input.value = "";

  if (formId) {
    triggerChangeOnForm(formId);
  } else {
    let form = input.closest("form");
    triggerChangeOnForm(form.id);
  }
};

// Trigger change on form by id
export const triggerChangeOnForm = (formId, fromSearchSearch) => {
  // When it is triggered from the search input
  if (fromSearchSearch) {
    const input = document.getElementById("ts_query");
    // Prevent form submission if the search input is empty
    if (input.value === "") {
      return;
    }
  }
  const form = document.getElementById(formId);
  htmx.trigger(form, "change");
};

// Load explore page with ts_query from search input on home page
export const loadExplorePageWithTsQuery = () => {
  const input = document.getElementById("ts_query");
  if (input.value !== "") {
    document.location.href = `/explore?ts_query=${input.value}`;
  }
};

// Trigger change on form on key down event on search input
export const onSearchKeyDown = (e, formId) => {
  if (e.key === "Enter") {
    if (formId === "") {
      const value = e.currentTarget.value;
      if (value !== "") {
        document.location.href = `/explore?ts_query=${value}`;
      }
    } else {
      triggerChangeOnForm(formId);
    }
    e.currentTarget.blur();
  }
};

// Check if collapsible filter is collapsed and active filters are hidden
export const checkVisibleFilters = () => {
  const collapsibleItems = document.querySelectorAll("[data-collapsible-item]");
  collapsibleItems.forEach((item) => {
    const filter = item.dataset.collapsibleLabel;
    const hiddenCheckedOptions = item.querySelectorAll(
      "li.hidden input:checked"
    );
    if (hiddenCheckedOptions.length > 0) {
      updateCollapsibleFilterStatus(filter);
    }
  });
};

// Expand or collapse collapsible filter
export const updateCollapsibleFilterStatus = (id) => {
  const collapsibles = document.querySelectorAll(
    `[data-collapsible-label='${id}']`
  );
  collapsibles.forEach((collapsible) => {
    const maxItems = collapsible.dataset.maxItems;
    const isCollapsed = collapsible.classList.contains("collapsed");
    if (isCollapsed) {
      collapsible.classList.remove("collapsed");
      collapsible
        .querySelectorAll("li")
        .forEach((el) => el.classList.remove("hidden"));
    } else {
      collapsible.classList.add("collapsed");
      collapsible
        .querySelectorAll("li[data-input-item]")
        .forEach((el, index) => {
          // Hide all items after the max_visible_items_number (add 1 to include the "Any" option)
          if (index >= maxItems) {
            el.classList.add("hidden");
          }
        });
    }
  });
};
