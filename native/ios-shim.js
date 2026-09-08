// Injected into www/index.html by .github/workflows/ios-release.yml for the
// Capacitor build only. The web build never includes this file.
//
// 1. navigator.vibrate() does not exist in iOS WebViews. Map the app's vibrate
//    patterns onto the native Haptics plugin (@capacitor/haptics).
// 2. Web Audio contexts created outside a user gesture start suspended on iOS
//    and the app reuses one context forever. Resume any suspended context on
//    the next touch so sounds are never silently dropped.
// 3. iOS auto-zooms into inputs with font-size < 16px and the fixed layout
//    then cannot be zoomed back out. Cap the viewport scale like SeshScore.
//    The bundle loader replaces <html> after unpacking, so re-apply the cap
//    whenever the document element changes.
(function () {
  'use strict';

  // --- viewport zoom cap ---------------------------------------------------
  var VIEWPORT = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
  function capViewport() {
    var head = document.head;
    if (!head) return;
    var meta = head.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'viewport');
      head.insertBefore(meta, head.firstChild);
    }
    if (meta.getAttribute('content') !== VIEWPORT) meta.setAttribute('content', VIEWPORT);
  }
  capViewport();
  // childList on the document itself fires exactly when <html> is swapped.
  new MutationObserver(capViewport).observe(document, { childList: true });
  document.addEventListener('DOMContentLoaded', capViewport);

  function haptics() {
    var c = window.Capacitor;
    return c && c.Plugins && c.Plugins.Haptics ? c.Plugins.Haptics : null;
  }

  function styleFor(ms) {
    return ms >= 100 ? 'HEAVY' : ms >= 50 ? 'MEDIUM' : 'LIGHT';
  }

  // --- haptics -------------------------------------------------------------
  if (typeof navigator.vibrate !== 'function') {
    navigator.vibrate = function (pattern) {
      var h = haptics();
      if (!h) return false;
      var segs = Array.isArray(pattern) ? pattern : [pattern];
      var at = 0;
      for (var i = 0; i < segs.length; i++) {
        var ms = Number(segs[i]) || 0;
        if (i % 2 === 0 && ms > 0) {
          (function (delay, style) {
            setTimeout(function () {
              try { h.impact({ style: style }); } catch (e) {}
            }, delay);
          })(at, styleFor(ms));
        }
        at += ms;
      }
      return true;
    };
  }

  // --- web audio -----------------------------------------------------------
  var Orig = window.AudioContext || window.webkitAudioContext;
  if (Orig) {
    var contexts = [];
    function TrackedAudioContext() {
      var ctx = new Orig();
      contexts.push(ctx);
      return ctx;
    }
    TrackedAudioContext.prototype = Orig.prototype;
    window.AudioContext = TrackedAudioContext;
    window.webkitAudioContext = TrackedAudioContext;

    function resumeAll() {
      for (var i = 0; i < contexts.length; i++) {
        var ctx = contexts[i];
        if (ctx.state === 'suspended') {
          try { ctx.resume(); } catch (e) {}
        }
      }
    }
    // Capture phase on document survives the loader's documentElement swap.
    document.addEventListener('touchend', resumeAll, true);
    document.addEventListener('pointerup', resumeAll, true);
    document.addEventListener('click', resumeAll, true);
  }
})();
