import { expect } from "@open-wc/testing";

import {
  appendCopySuffix,
  buildSessionEntries,
  initializeSessionsRemovalWarning,
  setCategoryValue,
  setEventReminderEnabled,
  setGalleryImages,
  setHosts,
  setRegistrationRequired,
  setSessions,
  setSponsors,
  setTags,
  updateMarkdownContent,
  updateTimezone,
} from "/static/js/dashboard/group/event-form-helpers.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";

describe("event form helpers", () => {
  let swal;

  beforeEach(() => {
    resetDom();
    swal = mockSwal();
  });

  afterEach(() => {
    resetDom();
    swal.restore();
  });

  it("adds the copy suffix only for non-empty names", () => {
    // Confirm it adds the copy suffix only for non-empty names.
    expect(appendCopySuffix(" Demo event ")).to.equal("Demo event (copy)");
    expect(appendCopySuffix("   ")).to.equal("");
    expect(appendCopySuffix(null)).to.equal("");
  });

  it("sets category by id and falls back to matching the option label", () => {
    // Build the DOM fixture to check it sets category by id and falls back to matching.
    document.body.innerHTML = `
      <select id="category_id">
        <option value="">Select a category</option>
        <option value="1">Workshop</option>
        <option value="2">Lightning Talks</option>
      </select>
    `;

    // Read the category id element to check it sets category by id and falls back.
    const select = document.getElementById("category_id");
    const changes = [];
    select.addEventListener("change", () => changes.push(select.value));

    // Exercise the flow to check it sets category by id and falls back to matching.
    setCategoryValue({ category_id: 2 });
    expect(select.value).to.equal("2");

    // Exercise the flow to check it sets category by id and falls back to matching.
    setCategoryValue({ category_name: " workshop " });
    expect(select.value).to.equal("1");
    expect(changes).to.deep.equal(["2", "1"]);
  });

  it("updates gallery images and tags with sanitized values", () => {
    // Build the DOM fixture to check it updates gallery images and tags with sanitized.
    document.body.innerHTML = `
      <gallery-field field-name="photos_urls"></gallery-field>
      <multiple-inputs field-name="tags"></multiple-inputs>
    `;

    // Read the DOM to check it updates gallery images and tags with sanitized values.
    const gallery = document.querySelector(
      'gallery-field[field-name="photos_urls"]',
    );
    const tags = document.querySelector('multiple-inputs[field-name="tags"]');

    // Prepare gallery images to check it updates gallery images and tags with sanitized.
    let galleryImages = [];
    gallery._setImages = (images) => {
      galleryImages = images;
    };

    // Prepare tags updated to check it updates gallery images and tags with sanitized.
    let tagsUpdated = 0;
    tags.requestUpdate = () => {
      tagsUpdated += 1;
    };

    // Exercise the flow to check it updates gallery images and tags with sanitized.
    setGalleryImages([" one.png ", "", "two.png", null]);
    setTags([" frontend ", "", "community "]);

    // Confirm it updates gallery images and tags with sanitized values.
    expect(galleryImages).to.deep.equal(["one.png", "two.png"]);
    expect(tags.items).to.deep.equal([
      { id: 0, value: "frontend" },
      { id: 1, value: "community" },
    ]);
    expect(tags._nextId).to.equal(2);
    expect(tagsUpdated).to.equal(1);
  });

  it("syncs registration and reminder toggles with their hidden fields", () => {
    // Build the DOM fixture to check it syncs registration and reminder toggles.
    document.body.innerHTML = `
      <input id="toggle_registration_required" type="checkbox" />
      <input id="registration_required" type="hidden" value="false" />
      <input id="toggle_event_reminder_enabled" type="checkbox" />
      <input id="event_reminder_enabled" type="hidden" value="false" />
    `;

    // Exercise the flow to check it syncs registration and reminder toggles with their.
    setRegistrationRequired(true);
    setEventReminderEnabled(false);

    // Confirm it syncs registration and reminder toggles with their hidden fields.
    expect(
      document.getElementById("toggle_registration_required").checked,
    ).to.equal(true);
    expect(document.getElementById("registration_required").value).to.equal(
      "true",
    );
    expect(
      document.getElementById("toggle_event_reminder_enabled").checked,
    ).to.equal(false);
    expect(document.getElementById("event_reminder_enabled").value).to.equal(
      "false",
    );
  });

  it("sets normalized hosts and sponsors on their components", () => {
    // Build the DOM fixture to check it sets normalized hosts and sponsors on their.
    document.body.innerHTML = `
      <user-search-selector field-name="hosts"></user-search-selector>
      <sponsors-section></sponsors-section>
    `;

    // Read the DOM to check it sets normalized hosts and sponsors on their components.
    const hosts = document.querySelector(
      'user-search-selector[field-name="hosts"]',
    );
    const sponsors = document.querySelector("sponsors-section");

    // Prepare hosts updated to check it sets normalized hosts and sponsors on their.
    let hostsUpdated = 0;
    let sponsorsUpdated = 0;
    hosts.requestUpdate = () => {
      hostsUpdated += 1;
    };
    sponsors.requestUpdate = () => {
      sponsorsUpdated += 1;
    };

    // Exercise the flow to check it sets normalized hosts and sponsors on their.
    setHosts([
      { user: { user_id: "1", username: "alice" } },
      { user_id: "2", username: "bob" },
      { foo: "bar" },
    ]);
    setSponsors([{ name: "ACME", level: 2 }, { name: "Community" }]);

    // Confirm it sets normalized hosts and sponsors on their components.
    expect(hosts.selectedUsers).to.deep.equal([
      { user_id: "1", username: "alice" },
      { user_id: "2", username: "bob" },
    ]);
    expect(hostsUpdated).to.equal(1);
    expect(sponsors.selectedSponsors).to.deep.equal([
      { name: "ACME", level: "2" },
      { name: "Community", level: "" },
    ]);
    expect(sponsorsUpdated).to.equal(1);
  });

  it("builds and applies normalized sessions for the sessions section", () => {
    // Build the DOM fixture to check it builds and applies normalized sessions.
    document.body.innerHTML = `<sessions-section></sessions-section>`;

    // Read the DOM to check it builds and applies normalized sessions for the sessions.
    const sessionsSection = document.querySelector("sessions-section");
    let initializeCalls = 0;
    let updateCalls = 0;
    sessionsSection._initializeSessionIds = () => {
      initializeCalls += 1;
    };
    sessionsSection.requestUpdate = () => {
      updateCalls += 1;
    };

    // Prepare sessions data to check it builds and applies normalized sessions.
    const sessionsData = {
      dayOne: [
        {
          name: "Opening keynote",
          description: "Kickoff",
          kind: "talk",
          location: "Main room",
          cfs_submission_id: 42,
          speakers: [
            {
              user: { user_id: "1", username: "alice" },
              featured: true,
            },
          ],
        },
      ],
      ignored: "not-an-array",
    };

    // Confirm it builds and applies normalized sessions for the sessions section.
    expect(buildSessionEntries(sessionsData)).to.deep.equal([
      {
        name: "Opening keynote",
        description: "Kickoff",
        kind: "talk",
        location: "Main room",
        meeting_join_instructions: "",
        meeting_join_url: "",
        meeting_recording_url: "",
        meeting_requested: false,
        meeting_in_sync: false,
        meeting_password: "",
        meeting_error: "",
        starts_at: "",
        ends_at: "",
        cfs_submission_id: "42",
        speakers: [{ user_id: "1", username: "alice", featured: true }],
      },
    ]);

    // Exercise the flow to check it builds and applies normalized sessions.
    setSessions(sessionsData);

    // Confirm it builds and applies normalized sessions for the sessions section.
    expect(sessionsSection.sessions).to.deep.equal(
      buildSessionEntries(sessionsData),
    );
    expect(initializeCalls).to.equal(1);
    expect(updateCalls).to.equal(1);
  });

  it("updates markdown content and timezone selectors", () => {
    // Build the DOM fixture to check it updates markdown content and timezone selectors.
    document.body.innerHTML = `
      <markdown-editor id="description">
        <textarea></textarea>
        <div class="CodeMirror"></div>
      </markdown-editor>
      <timezone-selector name="timezone"></timezone-selector>
    `;

    // Read the DOM to check it updates markdown content and timezone selectors.
    const editor = document.querySelector("markdown-editor#description");
    const textarea = editor.querySelector("textarea");
    const codeMirror = editor.querySelector(".CodeMirror");
    const timezoneSelector = document.querySelector(
      "timezone-selector[name='timezone']",
    );

    // Prepare input values to check it updates markdown content and timezone selectors.
    const inputValues = [];
    let savedValue = "";
    let timezoneChanges = 0;

    // Exercise the flow to check it updates markdown content and timezone selectors.
    textarea.addEventListener("input", () => inputValues.push(textarea.value));
    codeMirror.CodeMirror = {
      setValue(value) {
        savedValue = value;
      },
      save() {
        savedValue = `${savedValue}:saved`;
      },
    };
    timezoneSelector.addEventListener("change", () => {
      timezoneChanges += 1;
    });

    // Exercise the flow to check it updates markdown content and timezone selectors.
    updateMarkdownContent("## Agenda");
    updateTimezone("Europe/Madrid");

    // Confirm it updates markdown content and timezone selectors.
    expect(textarea.value).to.equal("## Agenda");
    expect(inputValues).to.deep.equal(["## Agenda"]);
    expect(savedValue).to.equal("## Agenda:saved");
    expect(timezoneSelector.value).to.equal("Europe/Madrid");
    expect(timezoneChanges).to.equal(1);
  });

  it("warns before removing sessions when saving without event dates", async () => {
    // Build the DOM fixture to check it warns before removing sessions when saving.
    document.body.innerHTML = `
      <input id="starts_at" value="" />
      <input id="ends_at" value="" />
      <button id="save-button" type="button">Save</button>
      <sessions-section></sessions-section>
    `;

    // Read the save button element to check it warns before removing sessions.
    const saveButton = document.getElementById("save-button");
    const sessionsSection = document.querySelector("sessions-section");
    let allowedClicks = 0;

    // Exercise the flow to check it warns before removing sessions when saving.
    sessionsSection.sessions = [{ name: "Opening keynote" }];
    saveButton.addEventListener("click", () => {
      allowedClicks += 1;
    });

    // Exercise the flow to check it warns before removing sessions when saving.
    initializeSessionsRemovalWarning({ saveButton });

    // Trigger the user interaction to check it warns before removing sessions.
    saveButton.click();
    await waitForMicrotask();

    // Confirm it warns before removing sessions when saving without event dates.
    expect(swal.calls).to.have.length(1);
    expect(swal.calls[0].text).to.include("will remove all sessions");
    expect(allowedClicks).to.equal(1);
  });
});
