if (document.cookie.split(";").some((c) => c.trim() === "ocg_viewport_mode=desktop")) {
  document.documentElement.setAttribute("data-viewport-mode", "desktop");
  document.querySelector('meta[name="viewport"]').setAttribute("content", "width=1280");
}
