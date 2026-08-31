import { expect } from "@open-wc/testing";

import "/static/js/common/location/search-field.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("location-search-field", () => {
  useMountedElementsCleanup("location-search-field");

  let fetchMock;

  beforeEach(() => {
    resetDom();
    fetchMock = mockFetch();
  });

  afterEach(() => {
    fetchMock.restore();
  });

  // Render a field with the standard venue field names used by location forms.
  const renderField = async (properties = {}) => {
    return mountLitComponent("location-search-field", {
      venueNameFieldName: "venue_name",
      venueAddressFieldName: "venue_address",
      venueCityFieldName: "venue_city",
      venueZipCodeFieldName: "venue_zip_code",
      stateFieldName: "venue_state_name",
      stateCodeFieldName: "venue_state_code",
      countryNameFieldName: "venue_country",
      countryCodeFieldName: "venue_country_code",
      latitudeFieldName: "venue_latitude",
      longitudeFieldName: "venue_longitude",
      ...properties,
    });
  };

  it("loads search results from nominatim", async () => {
    // Render the field fixture.
    const element = await renderField();

    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [
          {
            place_id: 1,
            display_name: "Málaga, Andalusia, Spain",
          },
        ];
      },
    }));

    // Run a Nominatim search for the typed location.
    await element._performSearch("Málaga");

    // The request uses the expected endpoint and options.
    expect(fetchMock.calls).to.have.length(1);
    expect(fetchMock.calls[0][0]).to.include("q=M%C3%A1laga");
    expect(fetchMock.calls[0][0]).to.include("addressdetails=1");
    expect(element._searchResults).to.deep.equal([
      {
        place_id: 1,
        display_name: "Málaga, Andalusia, Spain",
      },
    ]);
    expect(element._searchError).to.equal(null);
    expect(element._isSearching).to.equal(false);
  });

  it("searches with browser-safe request headers", async () => {
    // Render the field fixture.
    const element = await renderField();

    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [];
      },
    }));

    // Search with the default browser-safe request headers.
    await element._performSearch("Málaga");

    // The request only sends headers allowed by browser fetch.
    expect(fetchMock.calls[0][1].headers).to.deep.equal({
      Accept: "application/json",
    });
  });

  it("surfaces fetch errors without keeping stale results", async () => {
    // Render the field and seed stale search results.
    const element = await renderField();
    element._searchResults = [{ place_id: 99 }];

    // Mock a failed Nominatim response.
    fetchMock.setImpl(async () => ({
      ok: false,
      status: 503,
    }));

    // Search again after stale results already exist.
    await element._performSearch("Broken");

    // Failed searches clear stale results and expose the fetch error.
    expect(element._searchResults).to.deep.equal([]);
    expect(element._searchError).to.equal("HTTP error! status: 503");
    expect(element._abortController).to.equal(null);
  });

  it("ignores aborted searches without replacing the existing search state", async () => {
    // Render the field and seed existing search state.
    const element = await renderField();
    element._searchResults = [
      { place_id: 42, display_name: "Existing result" },
    ];
    element._searchError = "Previous error";

    // Mock an aborted Nominatim request.
    fetchMock.setImpl(async () => {
      const error = new Error("aborted");
      error.name = "AbortError";
      throw error;
    });

    // Search again while the request aborts.
    await element._performSearch("Málaga");

    // Aborted searches preserve previous results and clear loading state.
    expect(element._searchResults).to.deep.equal([
      { place_id: 42, display_name: "Existing result" },
    ]);
    expect(element._searchError).to.equal("Previous error");
    expect(element._isSearching).to.equal(false);
    expect(element._abortController).to.equal(null);
  });

  it("selects a location, populates internal and external fields, and emits an event", async () => {
    // Add the DOM fixture.
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <input id="venue-name-field" />
        <input id="venue-address-field" />
        <input id="venue-city-field" />
        <input id="venue-zip-field" />
        <input id="venue-state-field" />
        <input id="venue-country-field" />
        <input id="venue-lat-field" />
        <input id="venue-lng-field" />
      `,
    );

    // Render the field fixture.
    const element = await renderField({
      venueNameFieldId: "venue-name-field",
      venueAddressFieldId: "venue-address-field",
      venueCityFieldId: "venue-city-field",
      venueZipCodeFieldId: "venue-zip-field",
      stateFieldId: "venue-state-field",
      countryFieldId: "venue-country-field",
      latitudeFieldId: "venue-lat-field",
      longitudeFieldId: "venue-lng-field",
    });

    // Seed the fixture data.
    element._map = {
      remove() {},
      jumpTo() {},
      resize() {},
    };
    element._mapMarker = {
      setLngLat() {},
    };

    // Track emitted events.
    const selectedEvents = [];
    element.addEventListener("location-selected", (event) => {
      selectedEvents.push(event.detail);
    });

    // Select the location result.
    element._selectLocation({
      lat: "36.7213",
      lon: "-4.4214",
      type: "city",
      addresstype: "city",
      display_name: "Málaga, Andalusia, Spain",
      address: {
        city: "Málaga",
        postcode: "29001",
        state: "Andalusia",
        "ISO3166-2-lvl4": "ES-AN",
        "ISO3166-2-lvl6": "ES-MA",
        country: "Spain",
        country_code: "es",
        name: "Málaga",
      },
    });
    await element.updateComplete;
    await waitForMicrotask();

    // The selected event carries the expected payload.
    expect(element._venueCityValue).to.equal("Málaga");
    expect(element._countryCodeValue).to.equal("ES");
    expect(element._stateCodeValue).to.equal("MA");
    expect(element._latitudeValue).to.equal("36.7213");
    expect(document.getElementById("venue-city-field")?.value).to.equal(
      "Málaga",
    );
    expect(document.getElementById("venue-country-field")?.value).to.equal(
      "Spain",
    );
    expect(selectedEvents).to.deep.equal([
      {
        venueName: "Málaga",
        venueAddress: "",
        venueCity: "Málaga",
        venueZipCode: "29001",
        state: "Andalusia",
        stateCode: "MA",
        country: "Spain",
        countryCode: "ES",
        latitude: 36.7213,
        longitude: -4.4214,
        displayName: "Málaga, Andalusia, Spain",
      },
    ]);
  });

  it("sets complete location fields from an external payload", async () => {
    // Render the event venue field used by copy workflows.
    const element = await renderField();

    // Apply every persisted venue value through the public component API.
    element.setLocationFields({
      country: "Spain",
      countryCode: "ES",
      latitude: 36.7213,
      longitude: -4.4214,
      state: "Andalusia",
      stateCode: "MA",
      venueAddress: "Av. de José Ortega y Gasset, 201",
      venueCity: "Málaga",
      venueName: "FYCMA",
      venueZipCode: "29006",
    });
    await element.updateComplete;

    // Verify the generated form controls expose the complete submitted venue.
    expect(element.querySelector('[name="venue_name"]')?.value).to.equal(
      "FYCMA",
    );
    expect(element.querySelector('[name="venue_address"]')?.value).to.equal(
      "Av. de José Ortega y Gasset, 201",
    );
    expect(element.querySelector('[name="venue_city"]')?.value).to.equal(
      "Málaga",
    );
    expect(element.querySelector('[name="venue_state_name"]')?.value).to.equal(
      "Andalusia",
    );
    expect(element.querySelector('[name="venue_state_code"]')?.value).to.equal(
      "MA",
    );
    expect(element.querySelector('[name="venue_country"]')?.value).to.equal(
      "Spain",
    );
    expect(
      element.querySelector('[name="venue_country_code"]')?.value,
    ).to.equal("ES");
    expect(element.querySelector('[name="venue_zip_code"]')?.value).to.equal(
      "29006",
    );
    expect(element.querySelector('[name="venue_latitude"]')?.value).to.equal(
      "36.7213",
    );
    expect(element.querySelector('[name="venue_longitude"]')?.value).to.equal(
      "-4.4214",
    );
    const normalizedText = element.textContent.replace(/\s+/g, " ");
    const stateCodeInput = element.querySelector('[name="venue_state_code"]');
    const stateCodeLabel = element.querySelector(
      `label[for="${stateCodeInput.id}"]`,
    );
    expect(stateCodeLabel.textContent.trim()).to.equal("State/Province Code");
    expect(normalizedText).to.contain(
      "State or province code used to calculate taxes.",
    );
    expect(normalizedText).to.contain(
      "Country Code * (required for paid tickets)",
    );
    expect(normalizedText).to.contain("Country code used to calculate taxes.");
    expect(element.textContent).not.to.contain("ISO state or province code.");
    expect(element.textContent).not.to.contain("ISO country code.");
  });

  it("clears selected codes when location names are edited manually", async () => {
    // Render a selected venue with both tax location codes.
    const element = await renderField();
    element.setLocationFields({
      country: "Spain",
      countryCode: "ES",
      state: "Andalusia",
      stateCode: "AN",
    });
    await element.updateComplete;

    // Edit the visible location names after the search selection.
    const stateNameInput = element.querySelector('[name="venue_state_name"]');
    const countryNameInput = element.querySelector('[name="venue_country"]');
    stateNameInput.value = "Catalonia";
    stateNameInput.dispatchEvent(new Event("input", { bubbles: true }));
    countryNameInput.value = "Portugal";
    countryNameInput.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;

    // Manual name edits invalidate the previously selected codes.
    expect(element.querySelector('[name="venue_state_code"]')?.value).to.equal(
      "",
    );
    expect(
      element.querySelector('[name="venue_country_code"]')?.value,
    ).to.equal("");
  });

  it("preserves manual state-code overrides until the country or location changes", async () => {
    // Render a selected venue and manually correct its derived subdivision code.
    const element = await renderField({
      initialCountryName: "Spain",
      initialStateCode: "MA",
    });
    const stateCodeInput = element.querySelector('[name="venue_state_code"]');
    stateCodeInput.value = "ML";
    stateCodeInput.dispatchEvent(new Event("input", { bubbles: true }));
    expect(element._stateCodeValue).to.equal("ML");

    // Editing the country invalidates the prior code.
    const countryInput = element.querySelector('[name="venue_country"]');
    countryInput.value = "Portugal";
    countryInput.dispatchEvent(new Event("input", { bubbles: true }));
    await element.updateComplete;
    expect(element.querySelector('[name="venue_state_code"]')?.value).to.equal(
      "",
    );

    // Selecting another location replaces the code with its own best derivation.
    element._selectLocation({
      lat: "38.7223",
      lon: "-9.1393",
      display_name: "Lisbon, Portugal",
      address: {
        city: "Lisbon",
        country: "Portugal",
        country_code: "pt",
        "ISO3166-2-lvl4": "PT-11",
      },
    });
    expect(element._stateCodeValue).to.equal("11");
  });

  it("supports keyboard navigation and selects the highlighted result on enter", async () => {
    // Render the field fixture.
    const element = await renderField();
    const selected = [];
    const event = {
      key: "",
      preventDefaultCalled: 0,
      preventDefault() {
        this.preventDefaultCalled += 1;
      },
    };

    // Seed the fixture data.
    element._searchResults = [{ place_id: 1 }, { place_id: 2 }];
    element._selectLocation = (result) => {
      selected.push(result);
    };

    // Move to the first option.
    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._highlightedIndex).to.equal(0);

    // Move to the next option.
    event.key = "ArrowDown";
    element._handleKeydown(event);
    expect(element._highlightedIndex).to.equal(1);

    // Select the highlighted option.
    event.key = "Enter";
    element._handleKeydown(event);

    // The selected event carries the expected payload.
    expect(selected).to.deep.equal([{ place_id: 2 }]);
    expect(event.preventDefaultCalled).to.equal(3);
  });

  it("hides the dropdown instead of searching when enter is pressed with a short query", async () => {
    // Render the field fixture.
    const element = await renderField();
    const event = {
      key: "Enter",
      preventDefaultCalled: 0,
      preventDefault() {
        this.preventDefaultCalled += 1;
      },
    };

    // Seed the component state.
    element._searchQuery = "Má";
    element._showDropdown = true;
    element._searchResults = [];
    element._abortController = { abort() {} };

    // Press Enter on a query too short to search.
    element._handleKeydown(event);

    // Enter closes the dropdown when the query is too short.
    expect(element._showDropdown).to.equal(false);
    expect(element._searchResults).to.deep.equal([]);
    expect(event.preventDefaultCalled).to.equal(1);
    expect(fetchMock.calls).to.have.length(0);
  });

  it("keeps the search button clickable when focus moves from the input", async () => {
    // Render the field fixture.
    const element = await renderField();
    element._searchQuery = "Málaga";
    await element.updateComplete;

    // Mock the fetch response.
    fetchMock.setImpl(async () => ({
      ok: true,
      async json() {
        return [];
      },
    }));

    // Collect the search button and pointer event elements.
    const searchButton = [...element.querySelectorAll("button")].find(
      (button) => button.textContent.trim() === "Search",
    );
    const pointerEvent = new PointerEvent("pointerdown", {
      bubbles: true,
      cancelable: true,
    });

    // Dispatch the pointer event.
    searchButton.dispatchEvent(pointerEvent);
    searchButton.click();
    await waitForMicrotask();

    // The request uses the expected endpoint and options.
    expect(pointerEvent.defaultPrevented).to.equal(true);
    expect(fetchMock.calls).to.have.length(1);
  });

  it("clears current values, tears down the map, and emits a clear event", async () => {
    // Render the field fixture.
    const element = await renderField();
    const clearedEvents = [];
    let removed = 0;

    // Seed the component state.
    element._venueNameValue = "Palacio de Ferias";
    element._venueCityValue = "Málaga";
    element._stateCodeValue = "MA";
    element._latitudeValue = "36.7213";
    element._longitudeValue = "-4.4214";
    element._mapVisible = true;
    element._map = {
      remove() {
        removed += 1;
      },
    };

    // Listen for the emitted event.
    element.addEventListener("location-cleared", () => {
      clearedEvents.push(true);
    });

    // Reset the fixture state.
    element.clearLocationFields();

    // The field values, map instance, and clear event are all reset.
    expect(element._venueNameValue).to.equal("");
    expect(element._venueCityValue).to.equal("");
    expect(element._stateCodeValue).to.equal("");
    expect(element._latitudeValue).to.equal("");
    expect(element._longitudeValue).to.equal("");
    expect(element._mapVisible).to.equal(false);
    expect(element._map).to.equal(null);
    expect(removed).to.equal(1);
    expect(clearedEvents).to.have.length(1);
  });

  it("fits map bounds when a country result provides a bounding box", async () => {
    // Render the field fixture.
    const element = await renderField();
    const markerCalls = [];
    const fitBoundsCalls = [];
    const jumpToCalls = [];

    // Seed the component state.
    element._mapVisible = true;
    element._latitudeValue = "36.7213";
    element._longitudeValue = "-4.4214";
    element._mapBoundingBox = [36.68, 36.75, -4.49, -4.35];
    element._shouldFitBounds = true;
    element._map = {
      remove() {},
      fitBounds(bounds, options) {
        fitBoundsCalls.push({ bounds, options });
      },
      jumpTo(options) {
        jumpToCalls.push(options);
      },
      resize() {},
    };
    element._mapMarker = {
      setLngLat(coords) {
        markerCalls.push(coords);
      },
    };

    // Sync the map preview after the component has rendered.
    await element.updateComplete;
    await element._syncMapPreviewInternal();

    // Fits map bounds when a country result provides a bounding box.
    expect(markerCalls[0]).to.deep.equal([-4.4214, 36.7213]);
    expect(fitBoundsCalls.at(-1)).to.deep.equal({
      bounds: [
        [-4.49, 36.68],
        [-4.35, 36.75],
      ],
      options: { duration: 0 },
    });
    expect(jumpToCalls).to.deep.equal([]);
  });
});
