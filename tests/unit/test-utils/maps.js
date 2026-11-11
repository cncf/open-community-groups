/**
 * Mocks MapLibre's browser API without a WebGL context or remote tile requests.
 * @returns {object} Recorded maps, markers, popups, API, and cleanup helper.
 */
export const mockMapLibre = () => {
  const originalMapLibre = globalThis.maplibregl;
  const maps = [];
  const markers = [];
  const popups = [];

  class Map {
    constructor(options) {
      this.options = options;
      this.canvas = document.createElement("canvas");
      this.canvas.tabIndex = options.interactive === false ? -1 : 0;
      this.getContainer().append(this.canvas);
      this.controls = [];
      this.handlers = {};
      this.sources = {};
      this.layers = [];
      this.fitBoundsCalls = [];
      this.easeToCalls = [];
      this.jumpToCalls = [];
      this.setStyleCalls = [];
      this.zoom = options.zoom;
      this.keyboard = {
        disableRotation() {
          this.rotationDisabled = true;
        },
      };
      this.touchZoomRotate = {
        disableRotation() {
          this.rotationDisabled = true;
        },
      };
      this.bounds = {
        getSouthWest: () => ({ lat: 1, lng: 2 }),
        getNorthEast: () => ({ lat: 3, lng: 4 }),
        contains: () => true,
      };
      maps.push(this);
    }

    addControl(control, position) {
      this.controls.push({ control, position });
      return this;
    }

    addLayer(layer) {
      if (this.layers.some((entry) => entry.id === layer.id)) {
        throw new Error(
          `Layer with id "${layer.id}" already exists on this map.`,
        );
      }
      this.layers.push(layer);
      return this;
    }

    addSource(id, options) {
      if (this.sources[id]) {
        throw new Error(`Source "${id}" already exists.`);
      }
      this.sources[id] = {
        ...options,
        loaded: true,
        setData(data) {
          this.data = data;
        },
        // Returns the source specification with its current data, as GeoJSONSource does.
        serialize() {
          return structuredClone(
            Object.fromEntries(
              Object.entries(this).filter(
                ([key, value]) =>
                  key !== "loaded" && typeof value !== "function",
              ),
            ),
          );
        },
        getClusterExpansionZoom: async () => 10,
        getClusterLeaves: async () => this.sources[id].data.features,
      };
      return this;
    }

    easeTo(options) {
      this.easeToCalls.push(options);
      this.zoom = options.zoom ?? this.zoom;
      return this;
    }

    emit(name, event = {}) {
      this.handlers[name]?.forEach((handler) => handler(event));
      return this;
    }

    fitBounds(bounds, options) {
      this.fitBoundsCalls.push({ bounds, options });
      return this;
    }

    getBounds() {
      return this.bounds;
    }

    getCanvas() {
      return this.canvas;
    }

    getContainer() {
      return document.getElementById(this.options.container);
    }

    getMaxZoom() {
      return this.options.maxZoom;
    }

    getSource(id) {
      return this.sources[id];
    }

    getZoom() {
      return this.zoom;
    }

    isSourceLoaded(id) {
      return this.sources[id]?.loaded ?? false;
    }

    jumpTo(options) {
      this.jumpToCalls.push(options);
      return this;
    }

    on(name, handler) {
      this.handlers[name] ||= [];
      this.handlers[name].push(handler);
      return this;
    }

    querySourceFeatures(id) {
      return this.sourceFeatures || this.sources[id].data.features;
    }

    remove() {
      if (this.removed) return;
      this.removed = true;
      markers
        .filter((marker) => marker.map === this)
        .forEach((marker) => marker.remove());
      popups
        .filter((popup) => popup.map === this)
        .forEach((popup) => popup.remove());
      this.canvas.remove();
      this.emit("remove");
    }

    resize() {}

    // Records the swap and rebuilds the style from the transformed result, as MapLibre does for a
    // basemap that has no sources or layers of its own.
    setStyle(url, options = {}) {
      this.setStyleCalls.push({ options, url });
      const previousStyle = {
        layers: structuredClone(this.layers),
        sources: Object.fromEntries(
          Object.entries(this.sources).map(([id, source]) => [
            id,
            source.serialize(),
          ]),
        ),
        version: 8,
      };
      const nextStyle = { layers: [], sources: {}, version: 8 };
      const style = options.transformStyle
        ? options.transformStyle(previousStyle, nextStyle)
        : nextStyle;
      this.layers = [];
      this.sources = {};
      Object.entries(style.sources).forEach(([id, source]) =>
        this.addSource(id, source),
      );
      style.layers.forEach((layer) => this.addLayer(layer));
      this.emit("style.load");
      return this;
    }
  }

  class Marker {
    constructor(options) {
      this.options = options;
      this.element = options.element;
      this.element.classList.add("maplibregl-marker");
      markers.push(this);
    }

    addTo(map) {
      this.map = map;
      if (!this.element.hasAttribute("role")) {
        this.element.setAttribute("role", "button");
      }
      map.getContainer().append(this.element);
      return this;
    }

    getElement() {
      return this.element;
    }

    getLngLat() {
      return this.coordinates;
    }

    remove() {
      this.element.remove();
      this.map = null;
      return this;
    }

    setLngLat(coordinates) {
      this.coordinates = coordinates;
      return this;
    }

    setPopup(popup) {
      this.popup = popup;
      this.element.tabIndex = 0;
      return this;
    }

    togglePopup() {
      if (this.popup.map) {
        this.popup.remove();
      } else {
        this.popup.setLngLat(this.coordinates).addTo(this.map);
      }
      return this;
    }
  }

  class Popup {
    constructor(options) {
      this.options = options;
      this.handlers = {};
      this.element = document.createElement("div");
      this.element.className = `maplibregl-popup ${options.className || ""}`;
      popups.push(this);
    }

    addTo(map) {
      this.map = map;
      map.getContainer().append(this.element);
      if (this.options.focusAfterOpen !== false) {
        this.element.querySelector("a[href], button")?.focus();
      }
      return this;
    }

    getElement() {
      return this.element;
    }

    isOpen() {
      return Boolean(this.map);
    }

    on(name, handler) {
      this.handlers[name] ||= [];
      this.handlers[name].push(handler);
      return this;
    }

    remove() {
      const wasOpen = Boolean(this.map);
      this.element.remove();
      this.map = null;
      if (wasOpen) this.handlers.close?.forEach((handler) => handler());
      return this;
    }

    setDOMContent(content) {
      this.element.replaceChildren(content);
      return this;
    }

    setHTML(html) {
      this.element.innerHTML = html;
      return this;
    }

    setLngLat(coordinates) {
      this.coordinates = coordinates;
      return this;
    }
  }

  class Control {
    constructor(options) {
      this.options = options;
    }
  }

  const api = {
    Map,
    Marker,
    Popup,
    AttributionControl: Control,
    NavigationControl: Control,
  };
  globalThis.maplibregl = api;
  return {
    api,
    maps,
    markers,
    popups,
    restore() {
      maps.forEach((map) => map.remove());
      if (originalMapLibre) {
        globalThis.maplibregl = originalMapLibre;
      } else {
        delete globalThis.maplibregl;
      }
    },
  };
};
