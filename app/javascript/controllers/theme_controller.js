import { Controller } from "@hotwired/stimulus";

// Palettes layered on top of the dark theme. They keep data-theme="dark" so
// every dark-mode token and chart keeps working, and add data-palette.
const DARK_PALETTES = ["relay"];

export default class extends Controller {
  static values = { userPreference: String };

  connect() {
    this.startSystemThemeListener();
  }

  disconnect() {
    this.stopSystemThemeListener();
  }

  // Called automatically by Stimulus when the userPreferenceValue changes (e.g., after form submit/page reload)
  userPreferenceValueChanged() {
    this.applyTheme();
  }

  // Called when a theme radio button is clicked
  updateTheme(event) {
    this.applyPreference(event.currentTarget.value);
  }

  // Applies theme based on the userPreferenceValue (from server)
  applyTheme() {
    this.applyPreference(this.userPreferenceValue);
  }

  applyPreference(preference) {
    if (preference === "system") {
      this.setTheme(this.systemPrefersDark());
    } else if (DARK_PALETTES.includes(preference)) {
      this.setTheme(true, preference);
    } else {
      this.setTheme(preference === "dark");
    }
  }

  // Sets the data-theme (and optional data-palette) attribute and broadcasts a
  // `theme:change` event so imperative consumers (D3/SVG/canvas) can repaint
  // without polling.
  setTheme(isDark, palette = null) {
    const theme = isDark ? "dark" : "light";
    const root = document.documentElement;
    localStorage.theme = theme;
    if (palette) {
      localStorage.palette = palette;
      root.setAttribute("data-palette", palette);
    } else {
      localStorage.removeItem("palette");
      root.removeAttribute("data-palette");
    }
    root.setAttribute("data-theme", theme);
    root.dispatchEvent(
      new CustomEvent("theme:change", { detail: { theme, palette } }),
    );
  }

  systemPrefersDark() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  }

  handleSystemThemeChange = (event) => {
    // Only apply system theme changes if the user preference is currently 'system'
    if (this.userPreferenceValue === "system") {
      this.setTheme(event.matches);
    }
  };

  toggle() {
    const currentTheme = document.documentElement.getAttribute("data-theme");
    if (currentTheme === "dark") {
      this.setTheme(false);
    } else {
      this.setTheme(true);
    }
  }

  startSystemThemeListener() {
    this.darkMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    this.darkMediaQuery.addEventListener(
      "change",
      this.handleSystemThemeChange,
    );
  }

  stopSystemThemeListener() {
    if (this.darkMediaQuery) {
      this.darkMediaQuery.removeEventListener(
        "change",
        this.handleSystemThemeChange,
      );
    }
  }
}
