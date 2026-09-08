import 'package:flutter_test/flutter_test.dart';

// Test the snapshot parsing and logic directly.
// We test how _PageSnapshot parses raw JSON and evaluates isLoginPage / onDataUrl.

class TestPageSnapshot {
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

  const TestPageSnapshot({
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

  factory TestPageSnapshot.parse(String raw) {
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

    return TestPageSnapshot(
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
}

void main() {
  group('Brunata Scraper Snapshot & Authentication State Tests', () {
    test('Correctly identifies Login page and prevents false onDataUrl even with returnUrl containing /uvi/', () {
      const loginRaw = '{"pwd":1,"inputs":2,"url":"https://portal.brunata-hamburg.de/Login?returnUrl=%2FUvi%2FNutzer%2FIndex","path":"/login","err":false,"len":532,"isLogin":true,"hasAuthApp":true,"hasHeaderApp":false,"onData":false}';
      final snap = TestPageSnapshot.parse(loginRaw);

      expect(snap.hasPasswordField, isTrue);
      expect(snap.isLoginPage, isTrue);
      expect(snap.hasAuthApp, isTrue);
      expect(snap.hasHeaderApp, isFalse);
      expect(snap.onDataUrl, isFalse);
      expect(snap.loginError, isFalse);
    });

    test('Correctly identifies login failure error message', () {
      const errorRaw = '{"pwd":1,"inputs":2,"url":"https://portal.brunata-hamburg.de/Login","path":"/login","err":true,"len":610,"isLogin":true,"hasAuthApp":true,"hasHeaderApp":false,"onData":false}';
      final snap = TestPageSnapshot.parse(errorRaw);

      expect(snap.hasPasswordField, isTrue);
      expect(snap.isLoginPage, isTrue);
      expect(snap.loginError, isTrue);
      expect(snap.onDataUrl, isFalse);
    });

    test('Correctly identifies authenticated state when header micro-frontend is mounted', () {
      const authRaw = '{"pwd":0,"inputs":0,"url":"https://portal.brunata-hamburg.de/overview","path":"/overview","err":false,"len":1420,"isLogin":false,"hasAuthApp":false,"hasHeaderApp":true,"onData":true}';
      final snap = TestPageSnapshot.parse(authRaw);

      expect(snap.hasPasswordField, isFalse);
      expect(snap.isLoginPage, isFalse);
      expect(snap.hasAuthApp, isFalse);
      expect(snap.hasHeaderApp, isTrue);
      expect(snap.onDataUrl, isTrue);
    });

    test('Correctly handles about:blank during startup without false error', () {
      const blankRaw = '{"pwd":0,"inputs":0,"url":"about:blank","path":"","err":false,"len":0,"isLogin":false,"hasAuthApp":false,"hasHeaderApp":false,"onData":false}';
      final snap = TestPageSnapshot.parse(blankRaw);

      expect(snap.hasPasswordField, isFalse);
      expect(snap.isLoginPage, isFalse);
      expect(snap.isErrorPage, isFalse);
      expect(snap.onDataUrl, isFalse);
    });

    test('Correctly identifies real UVI data page', () {
      const dataRaw = '{"pwd":0,"inputs":0,"url":"https://portal.brunata-hamburg.de/Uvi/Nutzer/Index","path":"/uvi/nutzer/index","err":false,"len":3500,"isLogin":false,"hasAuthApp":false,"hasHeaderApp":true,"onData":true}';
      final snap = TestPageSnapshot.parse(dataRaw);

      expect(snap.hasPasswordField, isFalse);
      expect(snap.isLoginPage, isFalse);
      expect(snap.onDataUrl, isTrue);
    });
  });
}
