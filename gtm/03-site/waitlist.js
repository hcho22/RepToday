/* Rep Today waitlist form (US-WL02).
   One script serves every sign-up placement on both landing pages. It posts the
   visitor's email, Fit answer, beta choice and Source straight to Kit's public sign-up
   endpoint (the same one Kit's embed used), so no Rep Today server ever sees an address.
   The four posted field names below are the ones in tools/waitlist/contract.json;
   tools/waitlist/check-site.py fails when they drift apart. */
(function () {
  'use strict';

  var CONFIG = {
    // The one place the sign-up destination is set. Kit's public form endpoint.
    signupUrl: 'https://app.kit.com/forms/9786563/subscriptions',
    // Kit asks a suspicious post to pass an interactive check in an iframe it hosts.
    guardOrigin: 'https://app.kit.com',
    guardPath: '/forms/guards/',
    // Local development never posts to Kit: it posts to tools/waitlist/stub-receiver.py.
    localHosts: ['localhost', '127.0.0.1', '[::1]'],
    localSignupUrl: 'http://127.0.0.1:8799/signup',
    timeoutMs: 20000
  };

  // The four Source links (reptoday.app/tiktok and so on). This list is the contract file's
  // source_tags, and tools/waitlist/check-site.py fails when the two differ. A new Source is a
  // new Dispatch request plus a reviewed gr0wthlab change, never an edit here alone.
  var SOURCE_TAGS = ['tiktok', 'youtube', 'reddit', 'network'];
  var SOURCE_KEY = 'reptoday.source';

  var FIELDS = {
    email: 'email_address',
    fit: 'fields[fit]',
    beta: 'fields[beta_opt_in]',
    source: 'fields[source]'
  };

  var COPY = {
    inProgress: 'Joining...',
    submit: 'Join the waitlist',
    success: 'Check your email to confirm your address.',
    emailError: 'Add a valid email address.',
    fitError: 'Choose the answer that sounds most like you.',
    failed: 'That did not go through. Try again in a moment.'
  };

  function isLocal() {
    return CONFIG.localHosts.indexOf(window.location.hostname) !== -1;
  }

  // The destination for this page. A local page can be pointed at another stub by a test.
  function endpoints() {
    var found = { signupUrl: isLocal() ? CONFIG.localSignupUrl : CONFIG.signupUrl, guardOrigin: CONFIG.guardOrigin };
    if (isLocal()) {
      try {
        var test = JSON.parse(window.sessionStorage.getItem('waitlist.testEndpoints') || 'null');
        if (test && typeof test === 'object') {
          if (typeof test.signupUrl === 'string') { found.signupUrl = test.signupUrl; }
          if (typeof test.guardOrigin === 'string') { found.guardOrigin = test.guardOrigin; }
        }
      } catch (error) { /* storage unavailable: keep the defaults */ }
    }
    return found;
  }

  // The tag a path names: the whole path must be one of the four tags, in any letter case,
  // with an optional trailing slash. Only the path counts: no query string, no utm_* value,
  // no referrer, so nothing outside the four tags can ever be recorded as a tag.
  function tagForPath(pathname) {
    var match = /^\/([A-Za-z]+)\/?$/.exec(String(pathname));
    var tag = match ? match[1].toLowerCase() : '';
    return SOURCE_TAGS.indexOf(tag) === -1 ? null : tag;
  }

  // The visit's tag: the link this tab last arrived by. Another path (the plain address, the
  // other page variant, /privacy) leaves an existing tag in place; a later link replaces it.
  // The tag alone is kept in this tab's sessionStorage: no cookie, no identifier.
  function resolveVisit(pathname, storage) {
    var arrived = tagForPath(pathname);
    var kept = null;
    try {
      if (arrived) {
        storage.setItem(SOURCE_KEY, arrived);
      } else {
        kept = storage.getItem(SOURCE_KEY);
      }
    } catch (error) { /* storage unavailable: this page load still knows its own link */ }
    var tag = arrived || kept;
    return SOURCE_TAGS.indexOf(tag) === -1 ? null : tag;
  }

  var visit = null;
  try { visit = resolveVisit(window.location.pathname, window.sessionStorage); } catch (error) { visit = tagForPath(window.location.pathname); }

  // The Source the sign-up carries: the visit's tag, else unknown.
  function visitSource() {
    return visit || 'unknown';
  }

  window.RepTodayWaitlist = { sourceTags: SOURCE_TAGS, tagForPath: tagForPath, resolveVisit: resolveVisit };

  function looksLikeEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
  }

  function init(form) {
    var email = form.querySelector('input[type="email"]');
    var emailError = form.querySelector('[data-wl-error="email"]');
    var fitError = form.querySelector('[data-wl-error="fit"]');
    var radios = form.querySelectorAll('input[type="radio"]');
    var beta = form.querySelector('input[type="checkbox"]');
    var source = form.querySelector('input[type="hidden"]');
    var button = form.querySelector('button[type="submit"]');
    var status = form.querySelector('[data-wl-status]');
    var guardBox = form.querySelector('[data-wl-guard]');
    var sending = false;
    var guardFrame = null;
    var guardListener = null;

    function clearChoices() {
      for (var i = 0; i < radios.length; i += 1) { radios[i].checked = false; }
      beta.checked = false;
    }

    function setError(input, holder, message) {
      if (message) {
        holder.textContent = message;
        holder.hidden = false;
        if (input) { input.setAttribute('aria-invalid', 'true'); }
      } else {
        holder.textContent = '';
        holder.hidden = true;
        if (input) { input.removeAttribute('aria-invalid'); }
      }
    }

    function selectedFit() {
      for (var i = 0; i < radios.length; i += 1) {
        if (radios[i].checked) { return radios[i].value; }
      }
      return '';
    }

    function setStatus(message) { status.textContent = message; }

    function setBusy(busy) {
      sending = busy;
      button.disabled = busy;
      button.textContent = busy ? COPY.inProgress : COPY.submit;
      form.setAttribute('aria-busy', busy ? 'true' : 'false');
    }

    function finish() {
      form.setAttribute('data-wl-state', 'done');
      var fields = form.querySelectorAll('[data-wl-fields]');
      for (var i = 0; i < fields.length; i += 1) { fields[i].hidden = true; }
      setStatus(COPY.success);
      status.setAttribute('tabindex', '-1');
      status.focus();
    }

    function validate() {
      var problems = [];
      var value = email.value.trim();
      if (!value || !looksLikeEmail(value) || !email.validity.valid) {
        setError(email, emailError, COPY.emailError);
        problems.push(email);
      } else {
        setError(email, emailError, '');
      }
      if (!selectedFit()) {
        setError(radios[0], fitError, COPY.fitError);
        problems.push(radios[0]);
      } else {
        for (var i = 0; i < radios.length; i += 1) { radios[i].removeAttribute('aria-invalid'); }
        setError(null, fitError, '');
      }
      return problems;
    }

    function closeGuard() {
      if (guardListener) { window.removeEventListener('message', guardListener); guardListener = null; }
      if (guardFrame) { guardFrame.remove(); guardFrame = null; }
      guardBox.hidden = true;
    }

    // Kit's interactive check: shown in Kit's own iframe, trusted only from Kit's origin.
    function showGuard(url, target) {
      var parsed;
      try { parsed = new URL(url); } catch (error) { return false; }
      if (parsed.origin !== target.guardOrigin || parsed.pathname.indexOf(CONFIG.guardPath) !== 0) { return false; }
      closeGuard();
      guardFrame = document.createElement('iframe');
      guardFrame.title = 'Security check';
      guardFrame.src = parsed.href;
      guardFrame.setAttribute('scrolling', 'no');
      guardFrame.style.cssText = 'border:0;width:100%;height:0;max-width:100%';
      guardListener = function (event) {
        if (event.origin !== target.guardOrigin || !event.data || typeof event.data !== 'object') { return; }
        if (event.data.name === 'ckjs:guard:size' && guardFrame) {
          var height = Number(event.data.height);
          if (height > 0 && height < 1200) { guardFrame.style.height = height + 'px'; }
        } else if (event.data.name === 'ckjs:guard:confirmed') {
          closeGuard();
          setBusy(false);
          finish();
        }
      };
      window.addEventListener('message', guardListener);
      guardBox.appendChild(guardFrame);
      guardBox.hidden = false;
      setStatus('');
      return true;
    }

    function fail() {
      setBusy(false);
      setStatus(COPY.failed);
    }

    function send() {
      var target = endpoints();
      var body = new URLSearchParams();
      body.append(FIELDS.email, email.value.trim());
      body.append(FIELDS.fit, selectedFit());
      body.append(FIELDS.beta, beta.checked ? 'true' : 'false');
      body.append(FIELDS.source, source.value);
      var controller = typeof AbortController === 'function' ? new AbortController() : null;
      var timer = controller ? window.setTimeout(function () { controller.abort(); }, CONFIG.timeoutMs) : null;
      setBusy(true);
      setStatus('');
      fetch(target.signupUrl, {
        method: 'POST',
        body: body,
        headers: { Accept: 'application/json' },
        credentials: 'omit',
        signal: controller ? controller.signal : undefined
      }).then(function (response) {
        if (!response.ok) { throw new Error('status'); }
        return response.json();
      }).then(function (answer) {
        if (timer) { window.clearTimeout(timer); }
        if (answer && answer.status === 'success') {
          setBusy(false);
          finish();
        } else if (answer && answer.status === 'quarantined' && typeof answer.url === 'string') {
          if (!showGuard(answer.url, target)) { fail(); }
        } else if (answer && answer.errors) {
          setBusy(false);
          setError(email, emailError, COPY.emailError);
          email.focus();
        } else {
          fail();
        }
      }).catch(function () {
        if (timer) { window.clearTimeout(timer); }
        fail();
      });
    }

    form.addEventListener('submit', function (event) {
      event.preventDefault();
      if (sending) { return; }
      var problems = validate();
      if (problems.length) {
        setStatus('');
        problems[0].focus();
        return;
      }
      send();
    });

    // Browsers may restore a checked radio or box after a reload or a back-navigation: never keep one.
    form.reset();
    clearChoices();
    window.addEventListener('pageshow', function () {
      if (form.getAttribute('data-wl-state') !== 'done') { clearChoices(); }
      source.value = visitSource();
    });

    source.value = visitSource();
    form.hidden = false;
  }

  var forms = document.querySelectorAll('form[data-waitlist-form]');
  for (var i = 0; i < forms.length; i += 1) { init(forms[i]); }
}());
