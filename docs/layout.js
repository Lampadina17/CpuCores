const layoutScript = document.currentScript;
const siteRoot = new URL("./", layoutScript.src);
const siteUrl = (path = "") => new URL(path, siteRoot).href;

const pages = [
  { id: "overview", label: "Overview", path: "" },
  { id: "install", label: "Install", path: "install/" },
  { id: "support", label: "Support", path: "support/" },
  { id: "privacy", label: "Privacy", path: "privacy/" },
];

const actions = {
  overview: {
    label: "Get the app",
    href: siteUrl("install/"),
  },
  install: {
    label: "Latest release",
    href: "https://github.com/Lampadina17/CpuCores/releases/latest",
  },
  support: {
    label: "Report an issue",
    href: "https://github.com/Lampadina17/CpuCores/issues/new",
  },
  privacy: {
    label: "View source",
    href: "https://github.com/Lampadina17/CpuCores",
  },
};

class SiteHeader extends HTMLElement {
  connectedCallback() {
    const currentPage = this.getAttribute("page") || "overview";
    const action = actions[currentPage] || actions.overview;
    const navigation = pages
      .map(({ id, label, path }) => {
        const currentAttributes = id === currentPage
          ? ' class="active" aria-current="page"'
          : "";
        return '<a' + currentAttributes + ' href="' + siteUrl(path) + '">' + label + '</a>';
      })
      .join("");

    this.innerHTML =
      '<header class="site-header">' +
        '<div class="nav-shell glass-panel">' +
          '<a class="brand" href="' + siteUrl() + '" aria-label="CPU Cores home">' +
            '<img src="' + siteUrl("icon.png") + '" alt="" width="38" height="38">' +
            '<span>CPU Cores</span>' +
          '</a>' +
          '<nav class="primary-nav" aria-label="Primary navigation">' +
            navigation +
          '</nav>' +
          '<a class="nav-cta" href="' + action.href + '">' +
            action.label +
            ' <i class="bi bi-arrow-up-right" aria-hidden="true"></i>' +
          '</a>' +
        '</div>' +
      '</header>';
  }
}

class SiteFooter extends HTMLElement {
  connectedCallback() {
    this.innerHTML =
      '<footer class="site-footer">' +
        '<p>Lampadina_17 © 2026</p>' +
      '</footer>';
  }
}

customElements.define("site-header", SiteHeader);
customElements.define("site-footer", SiteFooter);
