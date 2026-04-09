import { expect } from "@open-wc/testing";

import "/static/js/common/location-search-field.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";
import { mockFetch } from "/tests/unit/test-utils/network.js";

describe("location-search-field", () => {
  const originalLeaflet = window.L;

  let fetchMock;

  beforeEach(() => {
    resetDom();
    fetchMock = mockFetch();
  });

  afterEach(() => {
    removeMountedElements("location-search-field");
    resetDom();
    fetchMock.restore();

    if (originalLeaflet) {
      window.L = originalLeaflet;
    } else {
      delete window.L;
    }
  });

  const renderField = async (properties = {}) => {
    return mountLitComponent("location-search-field", {
      venueNameFieldName: "venue_name",
      venueAddressFieldName: "venue_address",
      venueCityFieldName: "venue_city",
      venueZipCodeFieldName: "venue_zip_code",
      stateFieldName: "venue_state",
      countryNameFieldName: "venue_country",
      countryCodeFieldName: "venue_country_code",
      latitudeFieldName: "venue_latitude",
      longitudeFieldName: "venue_longitude",
      ...properties,
    });
  };

  it("loads search results from nominatim", async () => {
    const element = await renderField();

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

    await element._performSearch("Málaga");

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

  it("surfaces fetch errors without keeping stale results", async () => {
    const element = await renderField();
    element._searchResults = [{ place_id: 99 }];

    fetchMock.setImpl(async () => ({
      ok: false,
      status: 503,
    }));

    await element._performSearch("Broken");

    expect(element._searchResults).to.deep.equal([]);
    expect(element._searchError).to.equal("HTTP error! status: 503");
    expect(element._abortController).to.equal(null);
  });

  it("selects a location, populates internal and external fields, and emits an event", async () => {
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

    element._leafletMap = {
      remove() {},
      setView() {},
      invalidateSize() {},
    };
    element._leafletMarker = {
      setLatLng() {},
    };

    const selectedEvents = [];
    element.addEventListener("location-selected", (event) => {
      selectedEvents.push(event.detail);
    });

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
        country: "Spain",
        country_code: "es",
        name: "Málaga",
      },
    });
    await element.updateComplete;
    await waitForMicrotask();

    expect(element._venueCityValue).to.equal("Málaga");
    expect(element._countryCodeValue).to.equal("ES");
    expect(element._latitudeValue).to.equal("36.7213");
    expect(document.getElementById("venue-city-field")?.value).to.equal("Málaga");
    expect(document.getElementById("venue-country-field")?.value).to.equal("Spain");
    expect(selectedEvents).to.deep.equal([
      {
        venueName: "Málaga",
        venueAddress: "",
        venueCity: "Málaga",
        venueZipCode: "29001",
        state: "Andalusia",
        country: "Spain",
        countryCode: "ES",
        latitude: 36.7213,
        longitude: -4.4214,
        displayName: "Málaga, Andalusia, Spain",
      },
    ]);
  });

  it("supports keyboard navigation and selects the highlighted result on enter", async () => {
    const element = await renderField();
    const selected = [];
    const event = {
      key: "",
      preventDefaultCalled: 0,
      preventDefault() {
        this.preventDefaultCalled += 1;
      },
    };

    element._searchResults = [{ place_id: 1 }, { place_id: 2 }];
    element._selectLocation = (result) => {
      selected.push(result);
    };

    event.key = "ArrowDown";
    element._handleKeyDown(event);
    expect(element._highlightedIndex).to.equal(0);

    event.key = "ArrowDown";
    element._handleKeyDown(event);
    expect(element._highlightedIndex).to.equal(1);

    event.key = "Enter";
    element._handleKeyDown(event);

    expect(selected).to.deep.equal([{ place_id: 2 }]);
    expect(event.preventDefaultCalled).to.equal(3);
  });

  it("clears current values, tears down the map, and emits a clear event", async () => {
    const element = await renderField();
    const clearedEvents = [];
    let removed = 0;

    element._venueNameValue = "Palacio de Ferias";
    element._venueCityValue = "Málaga";
    element._latitudeValue = "36.7213";
    element._longitudeValue = "-4.4214";
    element._mapVisible = true;
    element._leafletMap = {
      remove() {
        removed += 1;
      },
    };

    element.addEventListener("location-cleared", () => {
      clearedEvents.push(true);
    });

    element.clearLocationFields();

    expect(element._venueNameValue).to.equal("");
    expect(element._venueCityValue).to.equal("");
    expect(element._latitudeValue).to.equal("");
    expect(element._longitudeValue).to.equal("");
    expect(element._mapVisible).to.equal(false);
    expect(element._leafletMap).to.equal(null);
    expect(removed).to.equal(1);
    expect(clearedEvents).to.have.length(1);
  });

  it("fits map bounds when a country result provides a bounding box", async () => {
    const element = await renderField();
    const markerCalls = [];
    const fitBoundsCalls = [];
    const setViewCalls = [];

    window.L = {
      latLngBounds: (southWest, northEast) => ({ southWest, northEast }),
    };

    element._mapVisible = true;
    element._latitudeValue = "36.7213";
    element._longitudeValue = "-4.4214";
    element._mapBoundingBox = [36.68, 36.75, -4.49, -4.35];
    element._shouldFitBounds = true;
    element._leafletMap = {
      remove() {},
      fitBounds(bounds, options) {
        fitBoundsCalls.push({ bounds, options });
      },
      setView(coords, zoom, options) {
        setViewCalls.push({ coords, zoom, options });
      },
      invalidateSize() {},
    };
    element._leafletMarker = {
      setLatLng(coords) {
        markerCalls.push(coords);
      },
    };

    await element.updateComplete;
    await element._syncMapPreviewInternal();

    expect(markerCalls[0]).to.deep.equal([36.7213, -4.4214]);
    expect(fitBoundsCalls.at(-1)).to.deep.equal({
      bounds: {
        southWest: [36.68, -4.49],
        northEast: [36.75, -4.35],
      },
      options: { animate: false },
    });
    expect(setViewCalls).to.deep.equal([]);
  });
});
