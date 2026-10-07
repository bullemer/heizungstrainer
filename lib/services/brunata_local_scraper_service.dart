/// Brunata portal local scraper service.
///
/// Uses a headless InAppWebView to log into the Brunata-Hamburg portal,
/// navigate to the billing dashboard, and extract consumption/cost data.
/// All processing happens client-side on the device — no data leaves the phone.
library;

import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Secure storage keys for Brunata credentials and settings.
abstract final class BrunataStorageKeys {
  static const username = 'brunata_username';
  static const password = 'brunata_password';
  static const portalUrl = 'brunata_portal_url';
  static const pricePerKwh = 'brunata_price_per_kwh';
}

/// Sync state for the Brunata scraping lifecycle.
enum BrunataSyncState {
  idle,
  initializing,
  loggingIn,
  navigating,
  scraping,
  complete,
  error,
}

/// Result of a Brunata portal sync attempt.
class BrunataSyncResult {
  final BrunataMeterData? data;
  final String? errorMessage;
  final bool success;

  const BrunataSyncResult.success(this.data)
      : errorMessage = null,
        success = true;

  const BrunataSyncResult.failure(this.errorMessage)
      : data = null,
        success = false;
}

/// Client-side headless web scraper for the Brunata-Hamburg billing portal.
///
/// The portal is a Vue / single-spa application: after a successful login it
/// changes route **client-side** (history.pushState) without a full document
/// reload. That means we cannot drive the flow from page load events
/// ([onLoadStop]) — the post-login transition would never be observed and the
/// sync would hang. Instead we poll the live [InAppWebViewController] on a
/// fixed cadence and run an explicit, time-bounded state machine:
///
/// 1. Wait for the login form (a password input) to render → inject credentials
///    and submit.
/// 2. Wait for the password field to disappear / the URL to leave the login
///    page (= authenticated), or detect an explicit login error.
/// 3. Poll the dashboard for consumption/cost values.
///
/// Every phase is bounded by elapsed time, so the method always resolves with a
/// concrete result and can never spin forever.
///
/// All credentials are stored/retrieved via [FlutterSecureStorage].
class BrunataLocalScraperService {
  final FlutterSecureStorage _secureStorage;

  /// Portal login URL (configurable).
  static const String defaultPortalUrl =
      'https://portal.brunata-hamburg.de/Login';

  /// Consumption overview page (year-to-date heating/warm-water in kWh).
  ///
  /// We load this directly instead of the login page: a valid (persisted)
  /// session opens it straight away, while an unauthenticated session is
  /// redirected to the login form by the portal. Loading `/Login` while already
  /// authenticated instead bounces to a 404 error page.
  static const String dataUrl =
      'https://portal.brunata-hamburg.de/Uvi/Nutzer/Index';

  /// Consumption views (Vue portal routes). These must be opened through the
  /// portal shell — it loads the matching `/legacy/...` page inside an iframe
  /// with the authenticated usage-unit context. Navigating to the `/legacy/...`
  /// URLs directly returns `/Home/UnAuthorized`, so we always use these routes
  /// and let the harvester read the iframe's `window.Highcharts.charts`
  /// (`series[].data[]` monthly kWh with an `isHochrechnung` flag for
  /// extrapolated months, plus `xAxis.categories` month labels).
  /// Usage-unit selection page — opening it establishes the active unit
  /// context the consumption iframes require.
  static const String nutzeinheitenUrl =
      'https://portal.brunata-hamburg.de/uvi/nutzeinheiten';

  static const String monthHeizungUrl =
      'https://portal.brunata-hamburg.de/Uvi/Nutzer/MonthCompare?mediumType=Heizung';
  static const String monthWarmwasserUrl =
      'https://portal.brunata-hamburg.de/Uvi/Nutzer/MonthCompare?mediumType=Warmwasser';
  static const String liegenschaftHeizungUrl =
      'https://portal.brunata-hamburg.de/Uvi/Nutzer/LiegenschaftCompare?mediumType=Heizung';
  static const String liegenschaftWarmwasserUrl =
      'https://portal.brunata-hamburg.de/Uvi/Nutzer/LiegenschaftCompare?mediumType=Warmwasser';

  /// Realistic heating benchmark price used when the user has not yet
  /// configured an explicit tariff (~12.8 ct/kWh).
  static const double defaultPricePerKwh = 0.128;

  /// Hard ceiling for the whole scraping flow (login + five consumption pages).
  static const Duration _overallTimeout = Duration(seconds: 150);

  /// Max time to wait for authentication to complete (form load + submit +
  /// redirect, or an already-valid session opening the data page).
  static const Duration _loginTimeout = Duration(seconds: 40);

  /// Max time to spend polling a single consumption page for chart data.
  static const Duration _scrapeTimeout = Duration(seconds: 18);

  /// Callback invoked on each scraper state transition.
  void Function(BrunataSyncState state)? onStateChange;

  BrunataLocalScraperService({
    FlutterSecureStorage? secureStorage,
    this.onStateChange,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ──────────────────────────────────────────────────────────────────
  // Credential Management
  // ──────────────────────────────────────────────────────────────────

  /// Stores Brunata login credentials securely on device.
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    await _secureStorage.write(
        key: BrunataStorageKeys.username, value: username);
    await _secureStorage.write(
        key: BrunataStorageKeys.password, value: password);
  }

  /// Whether valid Brunata login credentials are stored.
  Future<bool> hasCredentials() async {
    final user = await _secureStorage.read(key: BrunataStorageKeys.username);
    final pass = await _secureStorage.read(key: BrunataStorageKeys.password);
    return user != null && user.isNotEmpty && pass != null && pass.isNotEmpty;
  }

  /// Returns the stored username (or null if none).
  Future<String?> getUsername() =>
      _secureStorage.read(key: BrunataStorageKeys.username);

  /// Returns the stored password (or null if none).
  Future<String?> getPassword() =>
      _secureStorage.read(key: BrunataStorageKeys.password);

  /// Returns the configured portal URL, or [defaultPortalUrl] if unset.
  Future<String> getPortalUrl() async {
    final stored = await _secureStorage.read(key: BrunataStorageKeys.portalUrl);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    return defaultPortalUrl;
  }

  /// Saves the portal URL to secure storage.
  Future<void> savePortalUrl(String url) async {
    await _secureStorage.write(
      key: BrunataStorageKeys.portalUrl,
      value: url.trim(),
    );
  }

  /// Clears stored credentials.
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: BrunataStorageKeys.username);
    await _secureStorage.delete(key: BrunataStorageKeys.password);
  }

  // ──────────────────────────────────────────────────────────────────
  // Tariff (price per kWh)
  // ──────────────────────────────────────────────────────────────────

  /// Returns the configured price per kWh, or [defaultPricePerKwh] if unset.
  Future<double> getPricePerKwh() async {
    final raw = await _secureStorage.read(key: BrunataStorageKeys.pricePerKwh);
    if (raw == null || raw.isEmpty) return defaultPricePerKwh;
    final val = double.tryParse(raw);
    if (val == null || val <= 0) return defaultPricePerKwh;
    // Auto-migrate legacy 0.10 placeholder to realistic benchmark
    if (val == 0.10) return defaultPricePerKwh;
    return val;
  }

  /// Persists the price per kWh used to estimate costs.
  Future<void> savePricePerKwh(double price) async {
    await _secureStorage.write(
      key: BrunataStorageKeys.pricePerKwh,
      value: price.toString(),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Main Scraping Flow
  // ──────────────────────────────────────────────────────────────────

  /// Executes the full scraping pipeline.
  ///
  /// Returns a [BrunataSyncResult] with either the scraped data or an error.
  /// The headless WebView is always disposed regardless of outcome.
  Future<BrunataSyncResult> syncFromPortal() async {
    HeadlessInAppWebView? headlessWebView;

    try {
      final username =
          (await _secureStorage.read(key: BrunataStorageKeys.username))?.trim();
      final password =
          await _secureStorage.read(key: BrunataStorageKeys.password);

      if (username == null || password == null) {
        return const BrunataSyncResult.failure(
          'Keine Brunata-Zugangsdaten gespeichert. '
          'Bitte hinterlege deine Login-Daten.',
        );
      }

      _setState(BrunataSyncState.initializing);

      headlessWebView = HeadlessInAppWebView(
        // Start at the login page: when unauthenticated this reliably renders
        // the login form. An already-valid session bounces /Login to a 404
        // PostMessage page, which the auth loop recovers from by navigating to
        // the data page. (Starting at the data URL is unsafe: the unauthed Vue
        // shell briefly sits on a /uvi/ URL before the login form renders,
        // which would look like "already authenticated".)
        initialUrlRequest: URLRequest(url: WebUri(defaultPortalUrl)),
        initialSize: const Size(1080, 1920),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          useShouldOverrideUrlLoading: false,
          mediaPlaybackRequiresUserGesture: false,
          supportMultipleWindows: false,
          useWideViewPort: true,
          javaScriptCanOpenWindowsAutomatically: true,
          allowContentAccess: true,
          allowFileAccess: true,
          // Mimic a standard browser to avoid bot detection.
          userAgent:
              'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
        ),
        // Load events are used for diagnostics only — control flow is driven
        // by polling below so that client-side SPA navigation is handled.
        onLoadStop: (controller, url) {
          debugPrint('[Brunata] onLoadStop: $url');
        },
        onReceivedError: (controller, request, error) {
          debugPrint(
              '[Brunata] Load error: ${error.type} ${error.description} (${request.url})');
        },
        onReceivedHttpError: (controller, request, response) {
          debugPrint('[Brunata] HTTP ${response.statusCode}: ${request.url}');
        },
        onConsoleMessage: (controller, msg) {
          debugPrint('[Brunata] console: ${msg.message}');
        },
      );

      await headlessWebView.run();

      // The controller becomes available shortly after run(); wait for it.
      InAppWebViewController? controller = headlessWebView.webViewController;
      for (int i = 0; i < 25 && controller == null; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        controller = headlessWebView.webViewController;
      }
      if (controller == null) {
        return const BrunataSyncResult.failure(
          'Der interne Browser konnte nicht gestartet werden. '
          'Bitte versuche es erneut.',
        );
      }

      final overall = Stopwatch()..start();
      bool overBudget() => overall.elapsed >= _overallTimeout;

      // ── Phase 1: ensure we are authenticated ────────────────────────
      //
      // We loaded [dataUrl] directly. Three possible outcomes, all handled by
      // polling: (a) a valid session opens the data page straight away;
      // (b) no session → the portal redirects to the login form, which we fill
      // in and submit; (c) a transient error/landing page → we re-navigate to
      // the data page. We never assume a login form will appear.
      _setState(BrunataSyncState.loggingIn);
      final authClock = Stopwatch()..start();
      bool authenticated = false;
      bool injected = false;
      int postInjectCycles = 0;

      while (!overBudget() && authClock.elapsed < _loginTimeout) {
        final snap = await _snapshot(controller);
        debugPrint('[Brunata] auth snapshot: $snap');

        // Browser still launching from blank page — wait for actual page
        if (snap.url == 'about:blank' || snap.url.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }

        // Explicit login error (e.g. invalid credentials)
        if (snap.loginError && (snap.hasPasswordField || snap.isLoginPage)) {
          return const BrunataSyncResult.failure(
            'Anmeldung fehlgeschlagen. Bitte überprüfe deine '
            'Brunata-Zugangsdaten.',
          );
        }

        // Authenticated indicator: header micro-frontend mounted or genuine non-login data page
        if (snap.hasHeaderApp ||
            (snap.onDataUrl && !snap.isLoginPage && snap.bodyLength > 300)) {
          debugPrint(
              '[Brunata] Authenticated session confirmed: hasHeader=${snap.hasHeaderApp}, url=${snap.url}');
          authenticated = true;
          break;
        }

        // If credentials have been submitted:
        if (injected) {
          postInjectCycles++;
          // Navigated away from login page to an authenticated app route
          if (!snap.isLoginPage &&
              !snap.hasAuthApp &&
              snap.passwordFields == 0 &&
              snap.bodyLength > 300) {
            debugPrint(
                '[Brunata] Post-login navigation detected: url=${snap.url}');
            authenticated = true;
            break;
          }
          // If stuck on login page for > 8s after injection with password field still there and no error, allow retry
          if (postInjectCycles > 6 && snap.hasPasswordField) {
            debugPrint('[Brunata] Retrying login injection...');
            injected = false;
          }
        }

        // On login form and not yet submitted:
        if (!injected && (snap.hasPasswordField || snap.isLoginPage)) {
          if (snap.hasPasswordField) {
            final res = await controller.evaluateJavascript(
              source: _loginScript(username, password),
            );
            debugPrint('[Brunata] login injection result: $res');
            injected = true;
            postInjectCycles = 0;
            _setState(BrunataSyncState.navigating);
          }
        } else if (snap.isErrorPage) {
          // Transient/error landing (e.g. PostMessage 404) — reload login page
          debugPrint(
              '[Brunata] Transient error landing, reloading login: ${snap.url}');
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(defaultPortalUrl)),
          );
        }

        await Future.delayed(const Duration(milliseconds: 1200));
      }

      if (!authenticated) {
        return const BrunataSyncResult.failure(
          'Anmeldung fehlgeschlagen oder Sitzung ungültig. '
          'Bitte überprüfe deine Zugangsdaten und versuche es erneut.',
        );
      }

      // ── Phase 2: navigate the consumption pages and harvest charts ──
      _setState(BrunataSyncState.scraping);

      // Establish the active usage-unit context first. The portal selects the
      // unit when /uvi/nutzeinheiten is opened; the consumption pages render
      // empty iframes without it (this is skipped on the post-login redirect).
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(nutzeinheitenUrl)),
      );
      await Future.delayed(const Duration(seconds: 4));

      // The portal loads the matching /legacy/... page inside an iframe; the
      // harvester reads window.Highcharts.charts there.
      final pages = <String, String>{
        'index': dataUrl,
        'month_heizung': monthHeizungUrl,
        'month_warmwasser': monthWarmwasserUrl,
        'liegenschaft_heizung': liegenschaftHeizungUrl,
        'liegenschaft_warmwasser': liegenschaftWarmwasserUrl,
      };

      final harvests = <String, String>{};
      for (final entry in pages.entries) {
        if (overBudget()) break;
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(entry.value)),
        );
        await Future.delayed(const Duration(seconds: 2));

        // The ?mediumType=Warmwasser URL param is ignored by the shell, so on
        // warm-water pages we switch the medium control inside the page.
        if (entry.key.contains('warmwasser')) {
          final sw = await controller.evaluateJavascript(
            source: _selectMediumScript('Warmwasser'),
          );
          debugPrint('[Brunata] medium switch ${entry.key}: '
              '${(sw?.toString() ?? '').substring(0, (sw?.toString() ?? '').length.clamp(0, 1200))}');
          await Future.delayed(const Duration(seconds: 3));
        }

        final pageClock = Stopwatch()..start();
        String lastRaw = '';
        bool found = false;
        while (!overBudget() && pageClock.elapsed < _scrapeTimeout) {
          final raw = await controller.evaluateJavascript(
            source: _scrapeScript(0),
          );
          lastRaw = raw?.toString() ?? '';
          // Charts present once a series with data shows up.
          if (lastRaw.contains('"series":[{')) {
            found = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 2));
        }
        debugPrint(
            '[Brunata] harvest ${entry.key} (found=$found): ${lastRaw.substring(0, lastRaw.length.clamp(0, 3000))}');
        if (found) harvests[entry.key] = lastRaw;
      }

      if (harvests.isEmpty) {
        return const BrunataSyncResult.failure(
          'Verbrauchsdaten konnten nicht aus dem Portal gelesen werden.',
        );
      }
      final pricePerKwh = await getPricePerKwh();
      return _buildResult(harvests, pricePerKwh);
    } catch (e) {
      debugPrint('[Brunata] Fatal error: $e');
      return BrunataSyncResult.failure(
        'Synchronisierung fehlgeschlagen: $e',
      );
    } finally {
      try {
        await headlessWebView?.dispose();
        debugPrint('[Brunata] Headless WebView disposed.');
      } catch (e) {
        debugPrint('[Brunata] Error disposing WebView: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Page interaction scripts
  // ──────────────────────────────────────────────────────────────────

  /// Switches the medium (Heizung/Warmwasser) inside the page, searching the
  /// main document and every iframe for a matching `<select>` option, tab,
  /// button or link. Returns a diagnostic of the controls it found.
  String _selectMediumScript(String medium) => '''
    (function(medium) {
      var target = medium.toLowerCase();
      function inDoc(doc, label) {
        var rep = { f: label, selects: [], clicked: [], options: [] };
        if (!doc) return rep;
        try {
          var sels = doc.querySelectorAll('select');
          for (var i = 0; i < sels.length; i++) {
            var opts = [];
            for (var j = 0; j < sels[i].options.length; j++) {
              opts.push(sels[i].options[j].text.trim());
            }
            rep.selects.push({ id: sels[i].id || sels[i].name || '', opts: opts });
            for (var j2 = 0; j2 < sels[i].options.length; j2++) {
              if (sels[i].options[j2].text.toLowerCase().indexOf(target) >= 0) {
                sels[i].value = sels[i].options[j2].value;
                sels[i].dispatchEvent(new Event('change', { bubbles: true }));
                rep.clicked.push('select:' + sels[i].options[j2].text.trim());
              }
            }
          }
          var els = doc.querySelectorAll('a, button, [role="tab"], label, li, .nav-link');
          for (var k = 0; k < els.length; k++) {
            var t = (els[k].textContent || '').trim();
            var tl = t.toLowerCase();
            if (t.length > 0 && t.length < 24 &&
                (tl === target || tl.indexOf(target) >= 0)) {
              rep.options.push(t);
              try { els[k].click(); rep.clicked.push('click:' + t); } catch (e2) {}
            }
          }
        } catch (e) { rep.err = e.toString(); }
        return rep;
      }
      var out = { main: inDoc(document, 'main'), frames: [] };
      var ifr = document.querySelectorAll('iframe');
      for (var i = 0; i < ifr.length; i++) {
        try {
          var cd = ifr[i].contentDocument ||
              (ifr[i].contentWindow && ifr[i].contentWindow.document);
          out.frames.push(inDoc(cd, 'iframe[' + i + ']'));
        } catch (e) {
          out.frames.push({ f: 'iframe[' + i + ']', crossOrigin: true });
        }
      }
      return JSON.stringify(out);
    })('${_escapeJs(medium)}');
  ''';

  /// Reads a lightweight snapshot of the current page state.
  /// Reads a lightweight snapshot of the current page state.
  Future<_PageSnapshot> _snapshot(InAppWebViewController controller) async {
    const source = '''
      (function() {
        try {
          var authApp = document.getElementById('single-spa-application:@brunata/authentication');
          var headerApp = document.getElementById('single-spa-application:@brunata/header');
          var pwd = document.querySelectorAll('input[type=password]').length;
          var inputs = document.querySelectorAll('input').length;
          var body = document.body ? (document.body.innerText || '') : '';
          var lower = body.toLowerCase();
          var path = location.pathname.toLowerCase();
          var isLogin = path.indexOf('login') >= 0 || !!authApp || pwd > 0;
          var err = /ungült|ungueltig|falsche|falscher|nicht korrekt|incorrect|invalid|fehlgeschlagen/.test(lower);
          var onData = !isLogin && (path.indexOf('/uvi') >= 0 || !!headerApp || !!document.querySelector('iframe'));
          return JSON.stringify({
            pwd: pwd,
            inputs: inputs,
            url: location.href,
            path: path,
            err: err,
            len: body.length,
            isLogin: isLogin,
            hasAuthApp: !!authApp,
            hasHeaderApp: !!headerApp,
            onData: onData
          });
        } catch(e) {
          return JSON.stringify({
            pwd: 0,
            inputs: 0,
            url: location.href,
            path: '',
            err: false,
            len: 0,
            isLogin: false,
            hasAuthApp: false,
            hasHeaderApp: false,
            onData: false
          });
        }
      })();
    ''';
    final raw = await controller.evaluateJavascript(source: source);
    return _PageSnapshot.parse(raw?.toString() ?? '');
  }

  /// JS that locates the login fields, injects credentials (triggering Vue
  /// reactivity) and submits the form.
  String _loginScript(String username, String password) => '''
    (function() {
      try {
        // Dismiss cookie banner if present
        try {
          var btns = document.querySelectorAll('button');
          for (var b = 0; b < btns.length; b++) {
            if ((btns[b].textContent || '').trim().toLowerCase() === 'ausblenden') {
              btns[b].click();
              break;
            }
          }
        } catch(e) {}

        var inputs = document.querySelectorAll('input');
        var userField = document.getElementById('username') ||
                        document.querySelector('input[name="username"]');
        var passField = document.getElementById('password') ||
                        document.querySelector('input[name="password"]');

        if (!userField || !passField) {
          for (var i = 0; i < inputs.length; i++) {
            var inp = inputs[i];
            var type = (inp.type || '').toLowerCase();
            var name = (inp.name || '').toLowerCase();
            var id = (inp.id || '').toLowerCase();
            var placeholder = (inp.placeholder || '').toLowerCase();

            if (type === 'password') {
              passField = inp;
            } else if (type === 'text' || type === 'email' ||
                       name.indexOf('user') >= 0 || name.indexOf('login') >= 0 ||
                       name.indexOf('kunden') >= 0 || name.indexOf('nummer') >= 0 ||
                       id.indexOf('user') >= 0 || id.indexOf('login') >= 0 ||
                       placeholder.indexOf('kunden') >= 0 || placeholder.indexOf('nummer') >= 0 ||
                       placeholder.indexOf('benutzer') >= 0) {
              if (!userField) userField = inp;
            }
          }
        }

        if (!userField) {
          for (var j = 0; j < inputs.length; j++) {
            var t = (inputs[j].type || '').toLowerCase();
            if (t !== 'password' && t !== 'hidden' && t !== 'submit' && t !== 'checkbox') {
              userField = inputs[j];
              break;
            }
          }
        }

        if (!userField || !passField) {
          return JSON.stringify({status: 'error', message: 'Login-Felder nicht gefunden. inputs: ' + inputs.length});
        }

        var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;

        userField.focus();
        setter.call(userField, '${_escapeJs(username)}');
        userField.dispatchEvent(new Event('input', {bubbles: true}));
        userField.dispatchEvent(new Event('change', {bubbles: true}));
        userField.dispatchEvent(new Event('blur', {bubbles: true}));

        passField.focus();
        setter.call(passField, '${_escapeJs(password)}');
        passField.dispatchEvent(new Event('input', {bubbles: true}));
        passField.dispatchEvent(new Event('change', {bubbles: true}));
        passField.dispatchEvent(new Event('blur', {bubbles: true}));

        var submitBtn = document.querySelector('button[type="submit"]') ||
                        document.querySelector('input[type="submit"]') ||
                        document.querySelector('button.p-button-primary') ||
                        document.querySelector('button.login-btn') ||
                        document.querySelector('button.btn-primary') ||
                        document.querySelector('form button');

        if (!submitBtn) {
          var buttons = document.querySelectorAll('button');
          for (var k = 0; k < buttons.length; k++) {
            var txt = (buttons[k].textContent || '').toLowerCase();
            if (txt.indexOf('anmeld') >= 0 || txt.indexOf('login') >= 0 || txt.indexOf('einlog') >= 0) {
              submitBtn = buttons[k];
              break;
            }
          }
        }

        if (submitBtn) {
          setTimeout(function() { submitBtn.click(); }, 300);
          return JSON.stringify({status: 'ok', message: 'submit clicked'});
        }

        var form = document.querySelector('form');
        if (form) {
          setTimeout(function() { form.requestSubmit ? form.requestSubmit() : form.submit(); }, 300);
          return JSON.stringify({status: 'ok', message: 'form submitted'});
        }
        return JSON.stringify({status: 'error', message: 'Kein Submit-Element gefunden'});
      } catch(e) {
        return JSON.stringify({status: 'error', message: e.toString()});
      }
    })();
  ''';

  /// JS that extracts euro/kWh figures from the dashboard.
  ///
  /// The Brunata portal is a server-rendered ASP.NET app (jQuery + Highcharts)
  /// whose actual consumption content lives inside a same-origin `<iframe>` —
  /// the outer document only holds the header/cookie/footer shell. So this
  /// harvester walks the main window **and every reachable iframe** (one nested
  /// level), reading both the live `Highcharts.charts` object graph and the
  /// text. Per-frame diagnostics are always returned so the structure is
  /// visible in the logs when extraction comes up empty.
  String _scrapeScript(int attempt) => '''
    (function() {
      try {
        var euroCandidates = [];
        var kwhCandidates = [];
        var frameDiag = [];

        function harvest(win, doc, label) {
          var d = { f: label, bodyLen: 0, hc: 'absent', charts: [] };
          try {
            var body = (doc && doc.body) ? doc.body.innerText : '';
            d.bodyLen = body.length;
            d.text = body.replace(/\\s+/g, ' ').substring(0, 220);

            var m;
            var euroRegex = /([\\d.,]+)\\s*\\u20ac/g;
            while ((m = euroRegex.exec(body)) !== null) {
              var v = parseFloat(m[1].replace(/\\./g, '').replace(',', '.'));
              if (!isNaN(v) && v > 0 && v < 100000) euroCandidates.push(v);
            }
            var kwhRegex = /([\\d.,]+)\\s*kWh/gi;
            while ((m = kwhRegex.exec(body)) !== null) {
              var v2 = parseFloat(m[1].replace(/\\./g, '').replace(',', '.'));
              if (!isNaN(v2) && v2 > 0) kwhCandidates.push(v2);
            }

            var HC = win && win.Highcharts;
            if (HC) d.hc = HC.version || 'yes';
            if (HC && HC.charts) {
              for (var ci = 0; ci < HC.charts.length; ci++) {
                var c = HC.charts[ci];
                if (!c) continue;
                // Titles may embed a large <span data-modal …> help blob — keep
                // only the leading visible text.
                var title = ((c.title && c.title.textStr) || '').split('<')[0].trim();
                var subtitle = ((c.subtitle && c.subtitle.textStr) || '').split('<')[0].trim();
                var yUnit = '';
                try { yUnit = (c.yAxis && c.yAxis[0] && c.yAxis[0].axisTitle && c.yAxis[0].axisTitle.textStr) || ''; } catch(e1) {}
                var cats = null;
                try { cats = c.xAxis && c.xAxis[0] && c.xAxis[0].categories; } catch(e2) {}
                var seriesDiag = [];
                for (var si = 0; si < (c.series || []).length; si++) {
                  var s = c.series[si];
                  // Prefer options.data (preserves point objects incl. the
                  // isHochrechnung flag); fall back to the flat yData array.
                  var pts = (s.options && s.options.data && s.options.data.length)
                      ? s.options.data : (s.yData || []);
                  var nums = [];
                  var hr = [];
                  for (var di = 0; di < pts.length; di++) {
                    var pt = pts[di];
                    var y = pt, flag = false;
                    if (pt && typeof pt === 'object') {
                      y = (pt.y != null ? pt.y : (pt.length ? pt[1] : null));
                      flag = !!pt.isHochrechnung;
                    }
                    var n = parseFloat(y);
                    if (!isNaN(n)) { nums.push(n); hr.push(flag ? 1 : 0); }
                  }
                  var ctx = ((s.name || '') + ' ' + title + ' ' + subtitle + ' ' + yUnit).toLowerCase();
                  if (/kwh|kilowatt|w\\u00e4rme|waerme|heiz|energie|verbrauch/.test(ctx)) {
                    for (var k2 = 0; k2 < nums.length; k2++) if (nums[k2] > 0) kwhCandidates.push(nums[k2]);
                  }
                  if (/euro|kosten|\\u20ac|betrag/.test(ctx)) {
                    for (var k3 = 0; k3 < nums.length; k3++) if (nums[k3] > 0) euroCandidates.push(nums[k3]);
                  }
                  // Sum of the non-extrapolated (actual) points only.
                  var actualSum = 0;
                  for (var k = 0; k < nums.length; k++) if (!hr[k]) actualSum += nums[k];
                  seriesDiag.push({
                    name: s.name,
                    n: nums.length,
                    actualSum: Math.round(actualSum * 100) / 100,
                    data: nums.slice(0, 13),
                    hr: hr.slice(0, 13)
                  });
                }
                d.charts.push({ title: title, sub: subtitle, yUnit: yUnit, cats: cats ? cats.slice(0, 13) : null, series: seriesDiag });
              }
            }
          } catch (eh) {
            d.err = eh.toString();
          }
          frameDiag.push(d);
        }

        harvest(window, document, 'main');

        var iframes = document.querySelectorAll('iframe');
        for (var i = 0; i < iframes.length; i++) {
          var src = iframes[i].getAttribute('src') || '';
          var label = 'iframe[' + i + ']' + (src ? ':' + src : '');
          var cw = null, cd = null;
          try {
            cw = iframes[i].contentWindow;
            cd = iframes[i].contentDocument || (cw && cw.document);
          } catch (ex) {
            frameDiag.push({ f: label, crossOrigin: true, err: ex.toString() });
            continue;
          }
          if (!cd) { frameDiag.push({ f: label, note: 'no contentDocument' }); continue; }
          harvest(cw, cd, label);

          try {
            var inner = cd.querySelectorAll('iframe');
            for (var j = 0; j < inner.length; j++) {
              try {
                var w2 = inner[j].contentWindow;
                var d2 = inner[j].contentDocument || (w2 && w2.document);
                if (d2) harvest(w2, d2, label + '>iframe[' + j + ']');
              } catch (e3) {
                frameDiag.push({ f: label + '>iframe[' + j + ']', crossOrigin: true });
              }
            }
          } catch (e4) {}
        }

        var result = { cost: null, kwh: null, attempt: $attempt, url: location.href, diag: { frames: frameDiag } };
        if (kwhCandidates.length > 0) {
          kwhCandidates.sort(function(a, b) { return b - a; });
          result.kwh = kwhCandidates[0];
        }
        if (euroCandidates.length > 0) {
          euroCandidates.sort(function(a, b) { return b - a; });
          result.cost = euroCandidates[0];
        }
        return JSON.stringify(result);
      } catch(e) {
        return JSON.stringify({status: 'error', message: e.toString()});
      }
    })();
  ''';

  // ──────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────

  void _setState(BrunataSyncState state) {
    debugPrint('[Brunata] State: $state');
    onStateChange?.call(state);
  }

  /// Escapes a string for safe injection into a JavaScript string literal.
  static String _escapeJs(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  /// Builds the final [BrunataSyncResult] from the harvested page JSON.
  ///
  /// `consumedKwh` is the **year-to-date actual heating consumption**. Cost is
  /// derived from [pricePerKwh] because the portal exposes no € figure. The full
  /// set of parsed charts is preserved for the detail drill-down.
  BrunataSyncResult _buildResult(Map<String, String> harvests, double pricePerKwh) {
    try {
      final charts = _parseCharts(harvests);

      // YTD actual + full-year projection per medium, from the overview page.
      final heating = _ytdAndProjection(charts, warmWater: false);
      final warm = _ytdAndProjection(charts, warmWater: true);

      var heatingYtd = heating?.$1 ?? 0;
      final heatingProjection = heating?.$2 ?? 0;
      // Fallback: sum current-period actual months from MonthCompare.
      if (heatingYtd <= 0) {
        heatingYtd = _ytdActualHeating(harvests['month_heizung']) ?? 0;
      }
      final warmYtd = warm?.$1 ?? 0;
      final warmProjection = warm?.$2 ?? 0;

      if (heatingYtd <= 0) {
        return const BrunataSyncResult.failure(
          'Verbrauchsdaten wurden gelesen, aber kein gültiger '
          'Heizungs-Verbrauch erkannt.',
        );
      }

      final cost = heatingYtd * pricePerKwh;
      debugPrint('[Brunata] YTD actual heating: $heatingYtd kWh '
          '(projection $heatingProjection) → est. cost $cost € '
          '(@ $pricePerKwh €/kWh); warm water YTD $warmYtd; '
          '${charts.length} charts parsed');

      // Structure only (titles, series names, counts, sums) – no personal data.
      for (final c in charts) {
        debugPrint('[Brunata] Chart source=${c.source} title="${c.title}" unit="${c.unit}" '
            'categories=${c.categories.length} series=[${c.series.map((s) => '"${s.name}" n=${s.values.length} '
                'extrap=${s.extrapolated.where((e) => e).length} sum=${s.total.fixed(0)}').join('; ')}]');
      }
      final communityDiff =
          calculateCommunityComparisonPercentage(charts) ?? 0.0;
      debugPrint('[Brunata] Community comparison: $communityDiff%');

      final now = DateTime.now();
      return BrunataSyncResult.success(BrunataMeterData(
        currentBillingPeriodCost: cost,
        consumedKwh: heatingYtd,
        communityComparisonPercentage: communityDiff,
        periodStart: DateTime(now.year, 1, 1),
        periodEnd: DateTime(now.year, 12, 31),
        pricePerKwh: pricePerKwh,
        heatingYtdActual: heatingYtd,
        heatingProjection: heatingProjection,
        warmWaterYtdActual: warmYtd,
        warmWaterProjection: warmProjection,
        charts: charts,
      ));
    } catch (e) {
      debugPrint('[Brunata] Build result error: $e');
      return BrunataSyncResult.failure(
        'Daten konnten nicht verarbeitet werden: $e',
      );
    }
  }

  static const List<String> _monthLabels = [
    'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
  ];

  /// Parses every harvested page into a flat list of [BrunataChart]s (the data
  /// lives in the page's content iframe).
  List<BrunataChart> _parseCharts(Map<String, String> harvests) {
    final out = <BrunataChart>[];
    final seen = <String>{};
    harvests.forEach((key, raw) {
      final decoded = _decodeHarvest(raw);
      final frames = decoded?['diag']?['frames'];
      if (frames is! List) return;
      for (final f in frames) {
        final charts = (f is Map) ? f['charts'] : null;
        if (charts is! List) continue;
        for (final c in charts) {
          if (c is! Map) continue;
          final chart = _buildChart(key, c.cast<String, dynamic>());
          // Drop duplicates — e.g. when the warm-water page falls back to the
          // heating chart, the same title/data would appear twice.
          final dedupeKey = '${chart.title}|${chart.unit}';
          if (chart.title.isNotEmpty && !seen.add(dedupeKey)) continue;
          out.add(chart);
        }
      }
    });
    return out;
  }

  BrunataChart _buildChart(String source, Map<String, dynamic> json) {
    final series = <BrunataChartSeries>[
      for (final s in (json['series'] as List?) ?? const [])
        if (s is Map) BrunataChartSeries.fromJson(s.cast<String, dynamic>()),
    ];
    final maxLen =
        series.fold<int>(0, (m, s) => s.values.length > m ? s.values.length : m);

    var cats = <String>[
      for (final c in (json['cats'] as List?) ?? const [])
        _cleanLabel(c.toString()),
    ];
    if (cats.length != maxLen) {
      cats = (maxLen == 12)
          ? List.of(_monthLabels)
          : [for (var i = 0; i < maxLen; i++) '${i + 1}'];
    }

    return BrunataChart(
      source: source,
      title: _cleanLabel((json['title'] ?? '').toString()),
      subtitle: _cleanLabel((json['sub'] ?? '').toString()),
      unit: (json['yUnit'] ?? '').toString(),
      categories: cats,
      series: series,
    );
  }

  /// Strips embedded HTML from a portal label and collapses whitespace.
  String _cleanLabel(String s) {
    var t = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' – ');
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('&nbsp;', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Extracts (ytdActual, fullYearProjection) for one medium from the overview
  /// (`index`) charts. The current-period series is the one carrying an
  /// extrapolated point; its first value is the YTD actual, its last the trend.
  (double, double)? _ytdAndProjection(
    List<BrunataChart> charts, {
    required bool warmWater,
  }) {
    for (final c in charts) {
      if (c.source != 'index' || c.isWarmWater != warmWater) continue;
      BrunataChartSeries? current;
      for (final s in c.series) {
        if (s.extrapolated.any((e) => e)) {
          current = s;
          break;
        }
      }
      if (current == null) {
        for (final s in c.series) {
          if (s.name.toLowerCase().contains('aktuell')) {
            current = s;
            break;
          }
        }
      }
      current ??= c.series.isNotEmpty ? c.series.last : null;
      if (current != null && current.values.isNotEmpty) {
        final ytd = current.values.first;
        final proj =
            current.values.length > 1 ? current.values.last : ytd;
        return (ytd, proj);
      }
    }
    return null;
  }

  /// Returns the YTD actual heating consumption (kWh) from a harvested page.
  ///
  /// The current billing-period series is the one carrying extrapolated
  /// (`isHochrechnung`) months; summing only its actual months yields the
  /// year-to-date real consumption. Falls back to the largest actual-sum series
  /// if no extrapolation flags are present (e.g. a completed period).
  double? _ytdActualHeating(String? rawJson) {
    final decoded = _decodeHarvest(rawJson);
    if (decoded == null) return null;

    final series = <Map<String, dynamic>>[];
    final frames = decoded['diag']?['frames'];
    if (frames is List) {
      for (final f in frames) {
        final charts = (f is Map) ? f['charts'] : null;
        if (charts is! List) continue;
        for (final c in charts) {
          final cs = (c is Map) ? c['series'] : null;
          if (cs is! List) continue;
          for (final s in cs) {
            if (s is Map) series.add(s.cast<String, dynamic>());
          }
        }
      }
    }
    if (series.isEmpty) return null;

    double sumActual(Map<String, dynamic> s) {
      final data = s['data'];
      final hr = s['hr'];
      if (data is! List) return 0;
      double sum = 0;
      for (var i = 0; i < data.length; i++) {
        final flagged = hr is List && i < hr.length && (hr[i] == 1 || hr[i] == true);
        final v = data[i];
        if (!flagged && v is num) sum += v.toDouble();
      }
      return sum;
    }

    // Prefer the current-period series (has at least one extrapolated month).
    for (final s in series) {
      final hr = s['hr'];
      final hasExtrapolated =
          hr is List && hr.any((x) => x == 1 || x == true);
      if (hasExtrapolated) {
        final sum = sumActual(s);
        if (sum > 0) return sum;
      }
    }

    // Fallback: the series with the largest actual sum.
    double best = 0;
    for (final s in series) {
      final a = s['actualSum'];
      final v = (a is num) ? a.toDouble() : sumActual(s);
      if (v > best) best = v;
    }
    return best > 0 ? best : null;
  }

  /// Decodes a harvested page JSON string, tolerating double-encoding from the
  /// WebView bridge.
  Map<String, dynamic>? _decodeHarvest(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    try {
      final d = jsonDecode(s);
      if (d is Map<String, dynamic>) return d;
      if (d is String) {
        final d2 = jsonDecode(d);
        if (d2 is Map<String, dynamic>) return d2;
      }
    } catch (_) {
      // Not valid JSON (possibly truncated) — give up gracefully.
    }
    return null;
  }
}

/// Lightweight view of the current page used to drive the scraping state
/// machine.
class _PageSnapshot {
  final int passwordFields;
  final int inputs;
  final String url;
  final String path;
  final bool loginError;
  final int bodyLength;
  final bool isLoginPage;
  final bool hasAuthApp;
  final bool hasHeaderApp;
  final bool onData;

  const _PageSnapshot({
    required this.passwordFields,
    required this.inputs,
    required this.url,
    required this.path,
    required this.loginError,
    required this.bodyLength,
    required this.isLoginPage,
    required this.hasAuthApp,
    required this.hasHeaderApp,
    required this.onData,
  });

  bool get hasPasswordField => passwordFields > 0;

  bool get onDataUrl => onData;

  bool get isErrorPage {
    if (url.isEmpty || url == 'about:blank') return false;
    final u = url.toLowerCase();
    return u.contains('postmessage') ||
        u.contains('type=error') ||
        u.contains('/error');
  }

  /// Parses the JSON string produced by the in-page snapshot script. The value
  /// may arrive already-decoded or as a quoted/escaped string depending on the
  /// platform, so we extract fields with tolerant regexes.
  factory _PageSnapshot.parse(String raw) {
    int intField(String key) {
      final m = RegExp('"$key":(\\d+)').firstMatch(raw);
      return int.tryParse(m?.group(1) ?? '') ?? 0;
    }

    bool boolField(String key) {
      return RegExp('"$key":\\s*true').hasMatch(raw);
    }

    final urlMatch = RegExp(r'"url":"((?:[^"\\]|\\.)*)"').firstMatch(raw);
    final url = (urlMatch?.group(1) ?? '').replaceAll(r'\/', '/');

    final pathMatch = RegExp(r'"path":"((?:[^"\\]|\\.)*)"').firstMatch(raw);
    final path = (pathMatch?.group(1) ?? '').replaceAll(r'\/', '/');

    return _PageSnapshot(
      passwordFields: intField('pwd'),
      inputs: intField('inputs'),
      url: url,
      path: path,
      loginError: boolField('err'),
      bodyLength: intField('len'),
      isLoginPage: boolField('isLogin'),
      hasAuthApp: boolField('hasAuthApp'),
      hasHeaderApp: boolField('hasHeaderApp'),
      onData: boolField('onData'),
    );
  }

  @override
  String toString() =>
      'pwd=$passwordFields inputs=$inputs isLogin=$isLoginPage hasAuth=$hasAuthApp hasHeader=$hasHeaderApp err=$loginError onData=$onData len=$bodyLength url=$url';
}
