import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ---------------------------------------------------------------------------
// Per-client settings. Change these three lines for a new shop.
// `?app=1` tells the website it is running inside the app, so it hides its
// own "Download the app" banner and buttons.
// ---------------------------------------------------------------------------
const String kStoreUrl = 'https://sutofashionecom.netlify.app/?app=1';
const Color kBrand = Color(0xFF14213D); // status bar, splash
const Color kAccent = Color(0xFFC2185B); // progress bar, buttons

const Color kPaper = Color(0xFFF6F4F1);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: kBrand,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: kBrand,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const SutoApp());
}

class SutoApp extends StatelessWidget {
  const SutoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SUTO Fashion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: kAccent),
      home: const StorePage(),
    );
  }
}

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  late final WebViewController _web;
  final String _host = Uri.parse(kStoreUrl).host;

  int _progress = 0;
  bool _loaded = false;
  bool _offline = false;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kPaper)
      // Lets the site detect the app (window.SutoApp) and ask it to open links.
      ..addJavaScriptChannel('SutoApp', onMessageReceived: _onSiteMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (_) {
          if (mounted && _offline) setState(() => _offline = false);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onWebResourceError: (err) {
          // Only the page itself failing means "offline"; a broken image does not.
          if (err.isForMainFrame == true && mounted) {
            setState(() => _offline = true);
          }
        },
        onNavigationRequest: _onNavigation,
      ))
      ..loadRequest(Uri.parse(kStoreUrl));
  }

  /// Store pages stay inside the app. WhatsApp, phone, email, Instagram,
  /// Facebook and every other site open in their own apps.
  FutureOr<NavigationDecision> _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    if (!req.isMainFrame) return NavigationDecision.navigate;

    final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
    if (isWeb && uri.host == _host) return NavigationDecision.navigate;
    if (uri.scheme == 'about' || uri.scheme == 'data' || uri.scheme == 'blob') {
      return NavigationDecision.navigate;
    }
    _openOutside(uri);
    return NavigationDecision.prevent;
  }

  Future<void> _openOutside(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link')),
      );
    }
  }

  /// The website can call `SutoApp.postMessage('open:https://...')`.
  void _onSiteMessage(JavaScriptMessage msg) {
    final m = msg.message;
    if (m.startsWith('open:')) {
      final uri = Uri.tryParse(m.substring(5));
      if (uri != null) _openOutside(uri);
    }
  }

  /// Android back button:
  /// 1. close the site's open drawer / product page / image viewer
  /// 2. go back in page history
  /// 3. press twice to leave the app
  Future<void> _handleBack() async {
    try {
      final closed = await _web.runJavaScriptReturningResult(
          'window.__appBack ? window.__appBack() : false');
      if (closed == true || closed.toString() == 'true') return;
    } catch (_) {
      // page not ready yet; fall through
    }

    if (await _web.canGoBack()) {
      await _web.goBack();
      return;
    }

    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  void _retry() {
    setState(() {
      _offline = false;
      _loaded = false;
      _progress = 0;
    });
    _web.loadRequest(Uri.parse(kStoreUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: kBrand,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: kPaper,
                  child: WebViewWidget(controller: _web),
                ),
              ),
              if (_loaded && _progress < 100)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress / 100,
                    minHeight: 2.5,
                    color: kAccent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              if (_offline) Positioned.fill(child: _OfflineView(onRetry: _retry)),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _loaded,
                  child: AnimatedOpacity(
                    opacity: _loaded ? 0 : 1,
                    duration: const Duration(milliseconds: 400),
                    child: const _Splash(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kBrand,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset('assets/icon.png', width: 112, height: 112),
            ),
            const SizedBox(height: 20),
            const Text(
              'SUTO FASHION',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xB3FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kPaper,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 64, color: Color(0x9914213D)),
              const SizedBox(height: 16),
              const Text(
                'No internet connection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kBrand),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your connection and try again.\nইন্টারনেট সংযোগ দেখে আবার চেষ্টা করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF5B6476), height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                style: FilledButton.styleFrom(
                  backgroundColor: kAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
