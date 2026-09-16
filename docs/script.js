document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy");
    const originalContent = button.innerHTML;

    try {
      await navigator.clipboard.writeText(value);
      button.innerHTML = '<i class="bi bi-check2" aria-hidden="true"></i> Source URL copied';
      button.classList.add("copied");
    } catch {
      window.prompt("Copy this AltStore source URL:", value);
    }

    window.setTimeout(() => {
      button.innerHTML = originalContent;
      button.classList.remove("copied");
    }, 2200);
  });
});
