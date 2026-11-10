(() => {
  let storage = null;
  try {
    storage = window.localStorage;
  } catch {}
  const read = (key) => {
    try {
      return storage ? storage.getItem(key) : null;
    } catch {
      return null;
    }
  };
  const root = document.documentElement;

  try {
    const stored = read("ocg_theme");
    const query = "(prefers-color-scheme: dark)";
    const theme =
      stored === "light" || stored === "dark" ? stored : matchMedia(query).matches ? "dark" : "light";
    root.setAttribute("data-theme", theme);
    root.style.colorScheme = theme;
  } catch {}

  try {
    const name = "ocg_viewport_mode";
    let desktop = read(name) === "desktop";
    const legacy = document.cookie
      .split(";")
      .map((cookie) => cookie.trim())
      .find((cookie) => cookie.split("=")[0] === name);
    if (legacy !== undefined) {
      if (legacy === `${name}=desktop`) {
        desktop = true;
        try {
          storage.setItem(name, "desktop");
        } catch {}
      }
      const expiry = `${name}=; Path=/; Max-Age=0; SameSite=Lax`;
      const https = location.protocol === "https:";
      document.cookie = https ? `${expiry}; Secure` : expiry;
    }
    if (desktop) {
      root.setAttribute("data-viewport-mode", "desktop");
      document.querySelector('meta[name="viewport"]').setAttribute("content", "width=1280");
    }
  } catch {}
})();
