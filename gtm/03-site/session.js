/* Rep Today landing page: the scroll is a session.
   The pinned timer counts down, its bar fills, and the step list moves on as the page scrolls.
   That is all this script does. It reads the scroll position and never sets it: links jump by
   ordinary anchors, nothing listens to the wheel or to touches, and nothing is snapped or locked.
   Without it the page is a plain long page. It sends nothing and stores nothing. */
(function () {
  'use strict';

  var TOTAL_SECONDS = 105; // the "time left" a visitor starts with, 1:45
  var LAST_SECONDS = 3; // the app's timer turns to its last-seconds color from 0:03

  var clock = document.querySelector('[data-clock]');
  var time = document.querySelector('[data-clock-time]');
  var bar = document.querySelector('[data-clock-bar]');
  var now = document.querySelector('[data-clock-now]');
  var list = document.querySelector('[data-steps]');
  var sections = document.querySelectorAll('[data-step]');
  if (!clock || !time || !list || !sections.length) { return; }

  var items = list.querySelectorAll('li');
  var beats = document.querySelectorAll('[data-beat] .beat-bar > span');
  var reduced = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  var last = sections[sections.length - 1];
  var shown = { seconds: -1, step: -1 };
  var queued = false;

  function clamp(value) { return value < 0 ? 0 : (value > 1 ? 1 : value); }

  function label(seconds) {
    var rest = seconds % 60;
    return Math.floor(seconds / 60) + ':' + (rest < 10 ? '0' : '') + rest;
  }

  // The line a section has to cross to be the current one: a little under the pinned bar.
  function mark() {
    var rail = clock.parentNode.getBoundingClientRect();
    var pinnedAcross = rail.width > window.innerWidth * 0.6; // the small-screen bar, not the side column
    return (pinnedAcross ? rail.height : 0) + window.innerHeight * 0.22;
  }

  function update() {
    queued = false;
    var line = mark();
    var scrollTop = window.pageYOffset || document.documentElement.scrollTop || 0;
    var reach = document.documentElement.scrollHeight - window.innerHeight;

    // 0 at the top of the page, 1 once the last step (Done) reaches the line or the page ends.
    var end = last.getBoundingClientRect().top + scrollTop - line;
    if (reach > 0 && end > reach) { end = reach; }
    var progress = end > 0 ? clamp(scrollTop / end) : 1;

    var step = 0;
    for (var i = 0; i < sections.length; i += 1) {
      if (sections[i].getBoundingClientRect().top <= line) { step = i; }
    }
    if (progress >= 1) { step = sections.length - 1; }

    var seconds = Math.round(TOTAL_SECONDS * (1 - progress));
    if (seconds !== shown.seconds) {
      shown.seconds = seconds;
      time.textContent = label(seconds);
      if (seconds <= LAST_SECONDS) { clock.classList.add('is-last'); } else { clock.classList.remove('is-last'); }
    }
    if (bar) { bar.style.width = (progress * 100).toFixed(1) + '%'; }

    if (step !== shown.step) {
      shown.step = step;
      for (var j = 0; j < items.length; j += 1) {
        var link = items[j].querySelector('a');
        items[j].className = j < step ? 'is-done' : (j === step ? 'is-now' : '');
        if (link) {
          if (j === step) { link.setAttribute('aria-current', 'step'); } else { link.removeAttribute('aria-current'); }
        }
      }
      var name = items[step] && items[step].querySelector('.name');
      if (now && name) { now.textContent = name.textContent; }
    }

    // Each Rest bar fills while its beat crosses the screen. Left as drawn when motion is reduced.
    if (!(reduced && reduced.matches)) {
      for (var k = 0; k < beats.length; k += 1) {
        var box = beats[k].parentNode.getBoundingClientRect();
        var travelled = (window.innerHeight - box.top) / (window.innerHeight * 0.6);
        beats[k].style.width = (clamp(travelled) * 100).toFixed(1) + '%';
      }
    } else {
      for (var m = 0; m < beats.length; m += 1) { beats[m].style.width = ''; }
    }
  }

  function queue() {
    if (queued) { return; }
    queued = true;
    if (window.requestAnimationFrame) { window.requestAnimationFrame(update); } else { window.setTimeout(update, 16); }
  }

  window.addEventListener('scroll', queue, { passive: true });
  window.addEventListener('resize', queue);
  window.addEventListener('load', queue);
  if (reduced && reduced.addEventListener) { reduced.addEventListener('change', queue); }
  // A late font or an opened FAQ answer changes the page's length.
  document.addEventListener('toggle', queue, true);
  update();
}());
