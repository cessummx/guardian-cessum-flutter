import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'constants.dart';
import 'cessum_ui.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;
  bool _pageLoadedOk = false;
  int _progress = 0;

  StreamSubscription? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _watchConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _watchConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInternet = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (hasInternet && _wasOffline && _hasError) {
        _wasOffline = false;
        _retry();
      } else if (!hasInternet) {
        _wasOffline = true;
      }
    });
  }

  void _initWebView() {
    _pageLoadedOk = false;

    final params = const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);

    if (_controller.platform is AndroidWebViewController) {
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _hasError = false;
                _progress = 0;
              });
            }
          },
          onPageFinished: (url) {
            _pageLoadedOk = true;
            if (mounted) {
              setState(() {
                _loading = false;
                _hasError = false;
                _progress = 100;
              });
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (_pageLoadedOk) return;

            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && !_pageLoadedOk) {
                setState(() {
                  _loading = false;
                  _hasError = true;
                });
              }
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            if (uri.host.isNotEmpty && !uri.host.contains(moodleDomain)) {
              _openExternal(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(moodleUrl));
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _controller.reload();
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _loading = true;
      _pageLoadedOk = false;
      _progress = 0;
    });
    _controller.loadRequest(Uri.parse(moodleUrl));
  }

  // Volver al menu principal
  void _volverAlMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<bool> _onBackPressed() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onBackPressed();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          elevation: 2,
          title: const Text(
            'Aula Virtual',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recargar',
              onPressed: _refresh,
            ),
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'Inicio',
              onPressed: _volverAlMenu,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress > 0 && _progress < 100)
              LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(cessumGold),
                minHeight: 3,
              ),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    color: cessumRed,
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height - 160,
                          child: WebViewWidget(controller: _controller),
                        ),
                      ],
                    ),
                  ),
                  if (_loading && !_hasError && _progress < 10)
                    Container(
                      color: Colors.white,
                      child: const Center(
                        child: CircularProgressIndicator(color: cessumRed),
                      ),
                    ),
                  if (_hasError)
                    Container(
                      color: Colors.white,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.wifi_off,
                                  size: 64, color: cessumRed),
                              const SizedBox(height: 16),
                              const Text(
                                'No se pudo cargar la pagina',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Revisa tu conexion a internet. La app intentara reconectar automaticamente.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cessumMuted(context)),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cessumRed,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: _retry,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}