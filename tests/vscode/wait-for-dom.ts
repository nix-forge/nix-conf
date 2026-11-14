/** Observe DOM state with subscription before the initial snapshot. */
// oxlint-disable-next-line no-unused-vars -- CDP reads this native function declaration as source.
function waitForDOM(
  selector: string,
  minimumCount = 1,
  parentClass: string | null = null,
  timeout = 14000,
): Promise<boolean> {
  return new Promise((resolve, reject) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const observer = new MutationObserver(check);

    function finish(error?: unknown): void {
      observer.disconnect();
      clearTimeout(timer);
      if (error) reject(error);
      else resolve(true);
    }
    function check() {
      try {
        const elements = document.querySelectorAll(selector);
        if (
          elements.length >= minimumCount &&
          (!parentClass ||
            elements[0]?.parentElement?.classList.contains(parentClass))
        )
          finish();
      } catch (error) {
        finish(error);
      }
    }
    observer.observe(document, {
      subtree: true,
      childList: true,
      attributes: true,
    });
    timer = setTimeout(
      () => finish(new Error(`DOM condition timed out: ${selector}`)),
      timeout,
    );
    check();
  });
}
