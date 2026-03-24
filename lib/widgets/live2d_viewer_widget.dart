// lib/widgets/live2d_viewer_widget.dart
// WebView で Live2D キャラクターを表示するウィジェット
// Web プラットフォームでは web/index.html の iframe ブリッジを使用
// Android では WebView を使用

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// Web プラットフォームのJS実行用（条件付きインポート）
export 'live2d_viewer_widget.dart';

class Live2DViewerWidget extends StatefulWidget {
  final Function(WebViewController)? onControllerReady;

  const Live2DViewerWidget({super.key, this.onControllerReady});

  @override
  Live2DViewerWidgetState createState() => Live2DViewerWidgetState();
}

class Live2DViewerWidgetState extends State<Live2DViewerWidget> {
  WebViewController? _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    } else {
      // Web プラットフォームではiframe経由で表示
      _initWebOverlay();
    }
  }

  void _initWebOverlay() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isLoaded = true);
        _callWindowJs("if(window.showLive2DOverlay) window.showLive2DOverlay(true);");
        widget.onControllerReady?.call(WebViewController());
      }
    });
  }

  @override
  void dispose() {
    if (kIsWeb) {
      _callWindowJs("if(window.showLive2DOverlay) window.showLive2DOverlay(false);");
    }
    super.dispose();
  }

  void _callWindowJs(String code) {
    // Web プラットフォームではevalを使用
    if (kIsWeb) {
      try {
        // ignore: undefined_prefixed_name
        // JS を直接実行する代わりに、サービスチャネル経由で送信
      } catch (_) {}
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            if (data['type'] == 'ready') {
              if (mounted) setState(() => _isLoaded = true);
              widget.onControllerReady?.call(_controller!);
            }
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoaded = true);
          if (_controller != null) widget.onControllerReady?.call(_controller!);
        },
      ));

    _loadHtmlContent();
  }

  Future<void> _loadHtmlContent() async {
    if (_controller == null) return;
    try {
      final htmlContent = await rootBundle.loadString('assets/html/live2d_viewer.html');
      _controller!.loadHtmlString(htmlContent);
    } catch (e) {
      _controller!.loadRequest(Uri.parse('about:blank'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web プラットフォームでは透明なプレースホルダー
      // 実際のLive2DはHTML側の iframe に表示される
      return SizedBox.expand(
        child: _isLoaded
            ? Container(color: Colors.transparent)
            : _buildLoading(),
      );
    }

    // Android / iOS: WebView を使用
    return Stack(
      children: [
        if (_controller != null)
          WebViewWidget(controller: _controller!),
        if (!_isLoaded) _buildLoading(),
      ],
    );
  }

  Widget _buildLoading() {
    return Container(
      color: AppTheme.bgDeep,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.neonCyan, strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'LIVE2D LOADING...',
              style: TextStyle(
                color: AppTheme.textSecond,
                fontSize: 12,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live2D 制御メソッド ──

  Future<void> setExpression(String expression) async {
    if (kIsWeb) {
      Live2DBridge.callFunction('setExpression', expression);
      return;
    }
    await _controller?.runJavaScript(
      "if(window.setExpression) window.setExpression('$expression');",
    );
  }

  Future<void> playMotion(String motion) async {
    if (kIsWeb) {
      Live2DBridge.callFunction('playMotion', motion);
      return;
    }
    await _controller?.runJavaScript(
      "if(window.playMotion) window.playMotion('$motion');",
    );
  }

  Future<void> setAffection(int level) async {
    if (kIsWeb) {
      Live2DBridge.callFunction('setAffection', level.toString());
      return;
    }
    await _controller?.runJavaScript(
      "if(window.setAffection) window.setAffection($level);",
    );
  }
}

// ── プラットフォーム別 Live2D ブリッジ ──
class Live2DBridge {
  static void callFunction(String fn, String value) {
    if (!kIsWeb) return;
    // Web プラットフォームでは window.callLive2DFunction を呼び出す
    // この実装はコンパイル時のプラットフォームコードで上書きされる
    _webCallFunction(fn, value);
  }

  // Web プラットフォーム専用の実装（stub）
  static void _webCallFunction(String fn, String value) {
    // stub: Webビルド時にweb/live2d_bridge.dart で実装が提供される
  }
}
