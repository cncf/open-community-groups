import { expect } from "@open-wc/testing";

import {
  getAdBannerStorageKey,
  initializeFloatingAdBanners,
  isAdBannerClosed,
} from "/static/js/common/ad-banner.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const createFloatingBanner = ({ imageUrl = "https://example.com/banner.png", linkUrl = "" } = {}) => {
  const banner = document.createElement("div");
  const image = document.createElement("img");
  const closeButton = document.createElement("button");

  banner.dataset.adBanner = "floating";
  banner.dataset.adBannerImageUrl = imageUrl;
  banner.dataset.adBannerLinkUrl = linkUrl;
  banner.className = "translate-y-[150%]";
  closeButton.dataset.adBannerClose = "";
  image.src = imageUrl;
  banner.append(image, closeButton);

  return { banner, image, closeButton };
};

describe("advertisement banner", () => {
  beforeEach(() => {
    resetDom();
    localStorage.clear();
  });

  afterEach(() => {
    resetDom();
    localStorage.clear();
  });

  it("scopes closed state to the banner image and link URL", () => {
    const key = getAdBannerStorageKey("https://example.com/banner.png", "https://example.com/event");
    localStorage.setItem(key, "true");

    expect(isAdBannerClosed("https://example.com/banner.png", "https://example.com/event")).to.equal(true);
    expect(isAdBannerClosed("https://example.com/banner-new.png", "https://example.com/event")).to.equal(
      false,
    );
    expect(isAdBannerClosed("https://example.com/banner.png", "https://example.com/group")).to.equal(false);
  });

  it("animates in after the banner image loads", () => {
    const { banner, image } = createFloatingBanner();
    document.body.append(banner);

    initializeFloatingAdBanners(document);
    expect(banner.classList.contains("translate-y-0")).to.equal(false);

    image.dispatchEvent(new Event("load"));

    expect(banner.classList.contains("translate-y-0")).to.equal(true);
    expect(banner.classList.contains("translate-y-[150%]")).to.equal(false);
    expect(banner.hasAttribute("hidden")).to.equal(false);
  });

  it("hides and stores the current banner when closed", () => {
    const imageUrl = "https://example.com/banner.png";
    const linkUrl = "https://example.com/event";
    const { banner, closeButton } = createFloatingBanner({ imageUrl, linkUrl });
    document.body.append(banner);

    initializeFloatingAdBanners(document);
    closeButton.click();

    expect(banner.hasAttribute("hidden")).to.equal(true);
    expect(localStorage.getItem(getAdBannerStorageKey(imageUrl, linkUrl))).to.equal("true");
  });

  it("shows a changed banner after a previous one was closed", () => {
    const oldKey = getAdBannerStorageKey("https://example.com/banner.png", "https://example.com/event");
    const { banner, image } = createFloatingBanner({
      imageUrl: "https://example.com/banner.png",
      linkUrl: "https://example.com/group",
    });
    localStorage.setItem(oldKey, "true");
    document.body.append(banner);

    initializeFloatingAdBanners(banner);
    image.dispatchEvent(new Event("load"));

    expect(banner.hasAttribute("hidden")).to.equal(false);
    expect(banner.classList.contains("translate-y-0")).to.equal(true);
  });
});
