/* Boardhop marketing site behaviour.
 *
 * Three things, all progressive enhancement: reveal-on-scroll, the pinned
 * phone that swaps its shot as the feature copy scrolls past, and a border on
 * the header once the page has moved. With JS off, every reveal element is
 * already visible (the no-js class below is removed only when this runs) and
 * each feature step carries its own inline shot.
 */
(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* --------------------------------------------------------- reveals */

  function setUpReveals() {
    var items = document.querySelectorAll("[data-reveal]");
    if (!("IntersectionObserver" in window) || reduced) {
      items.forEach(function (el) {
        el.classList.add("is-revealed");
      });
      return;
    }
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-revealed");
          io.unobserve(entry.target);
        });
      },
      // Fire a little before the element reaches the fold, so the motion has
      // finished by the time it is properly in view.
      { rootMargin: "0px 0px -12% 0px", threshold: 0.08 }
    );
    items.forEach(function (el) {
      io.observe(el);
    });
  }

  /* ----------------------------------------------- pinned shot swapper */

  function setUpShowcase() {
    var stage = document.querySelector("[data-showcase-stage]");
    var steps = Array.prototype.slice.call(
      document.querySelectorAll("[data-step]")
    );
    if (!stage || !steps.length) return;

    var shots = {};
    stage.querySelectorAll("img[data-shot]").forEach(function (img) {
      shots[img.getAttribute("data-shot")] = img;
    });

    var current = null;
    function activate(key) {
      if (key === current) return;
      current = key;
      Object.keys(shots).forEach(function (k) {
        shots[k].classList.toggle("is-active", k === key);
      });
      steps.forEach(function (step) {
        step.classList.toggle("is-active", step.getAttribute("data-step") === key);
      });
    }

    activate(steps[0].getAttribute("data-step"));

    if (!("IntersectionObserver" in window)) {
      // Without an observer the first shot simply stays put; the copy is all
      // readable and each step still has its inline image on narrow screens.
      steps.forEach(function (s) {
        s.classList.add("is-active");
      });
      return;
    }

    // A thin band across the middle of the viewport: whichever step crosses it
    // owns the phone. This is steadier than "most visible", which flickers
    // between two steps of unequal height.
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            activate(entry.target.getAttribute("data-step"));
          }
        });
      },
      { rootMargin: "-48% 0px -48% 0px", threshold: 0 }
    );
    steps.forEach(function (step) {
      io.observe(step);
    });
  }

  /* ----------------------------------------------------- sticky header */

  function setUpNav() {
    var nav = document.querySelector("[data-nav]");
    if (!nav) return;
    var tick = function () {
      nav.setAttribute("data-stuck", window.scrollY > 8 ? "true" : "false");
    };
    tick();
    window.addEventListener("scroll", tick, { passive: true });
  }

  /* --------------------------------------------------------- year stamp */

  function setUpYear() {
    document.querySelectorAll("[data-year]").forEach(function (el) {
      el.textContent = String(new Date().getFullYear());
    });
  }

  function init() {
    // The no-js class is already gone: an inline script in <head> removes it
    // before first paint, so the reveal styles never flash in.
    setUpNav();
    setUpReveals();
    setUpShowcase();
    setUpYear();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
