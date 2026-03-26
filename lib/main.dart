// lib/main.dart
// Vtuber Chat - Full-screen WebView App
// web/index.html をAndroidでそのまま表示 + API proxy

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;

const int _localServerPort = 18080;

// ── API設定 ──
const String _aivisModelUuid = 'a670e6b8-0852-45b2-8704-1bc9862f2fe6';
const String _aivisApiUrl = 'https://api.aivis-project.com/v1/tts/synthesize';
const int _aivisTimeout = 30;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF050810),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const VtuberChatApp());
}

class VtuberChatApp extends StatelessWidget {
  const VtuberChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vtuber Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050810),
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});
  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  HttpServer? _localServer;

  // APIキー（env.txtから読み込み、フォールバックあり）
  String _openaiApiKey = ''; // env.txtから読み込み
  String _aivisApiKey = ''; // env.txtから読み込み

  @override
  void initState() {
    super.initState();
    _startLocalServerAndLoad();
  }

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }

  /// env.txt ファイルからAPIキーを読み込む（ドットファイルはFlutterアセットに含まれないためenv.txtを使用）
  Future<void> _loadEnvFile(String webDirPath) async {
    try {
      // env.txt を優先、.env もフォールバック
      for (final name in ['env.txt', '.env']) {
        final envFile = File('$webDirPath/$name');
        if (await envFile.exists()) {
          final lines = await envFile.readAsLines();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
            final idx = trimmed.indexOf('=');
            if (idx < 0) continue;
            final key = trimmed.substring(0, idx).trim();
            final value = trimmed.substring(idx + 1).trim();
            if (key == 'OPENAI_API_KEY') _openaiApiKey = value;
            if (key == 'AIVIS_API_KEY') _aivisApiKey = value;
          }
          debugPrint('Loaded API keys from $name');
          return;
        }
      }
      debugPrint('No env file found, using hardcoded keys');
    } catch (e) {
      debugPrint('Failed to load env: $e');
    }
  }

  Future<void> _startLocalServerAndLoad() async {
    try {
      setState(() { _isLoading = true; _error = null; });

      // 1. assets/webapp/ を一時ディレクトリにコピー
      final tempDir = await getTemporaryDirectory();
      final webDir = Directory('${tempDir.path}/webapp');
      if (await webDir.exists()) {
        await webDir.delete(recursive: true);
      }
      await webDir.create(recursive: true);
      await _copyAssetsToDir(webDir.path);

      // 2. .envからAPIキーを読み込み
      await _loadEnvFile(webDir.path);

      // 3. ローカルHTTPサーバーを起動（APIプロキシ付き）
      try { _localServer?.close(force: true); } catch (_) {}
      // ポート転用対策: shared=trueで再バインド可能に
      _localServer = await HttpServer.bind('127.0.0.1', _localServerPort, shared: true);
      debugPrint('Local server started on port $_localServerPort');

      _localServer!.listen((HttpRequest request) async {
        try {
          final path = request.uri.path;

          // API プロキシ
          if (request.method == 'POST' && path == '/api/chat') {
            await _handleChatProxy(request);
            return;
          }
          if (request.method == 'POST' && path == '/api/tts') {
            await _handleTtsProxy(request);
            return;
          }
          if (request.method == 'OPTIONS') {
            request.response
              ..statusCode = 200
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
              ..headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
            await request.response.close();
            return;
          }

          // 静的ファイル配信
          var filePath = path == '/' ? '/index.html' : path;
          final file = File('${webDir.path}$filePath');

          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.parse(_getMimeType(filePath))
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..headers.add('Cache-Control', 'no-cache')
              ..add(bytes);
          } else {
            request.response
              ..statusCode = 404
              ..write('Not Found: $filePath');
          }
          await request.response.close();
        } catch (e) {
          try {
            request.response
              ..statusCode = 500
              ..write('Server Error');
            await request.response.close();
          } catch (_) {}
        }
      });

      // 4. WebView初期化
      _initWebView();
    } catch (e) {
      setState(() { _error = 'Failed to start: $e'; _isLoading = false; });
    }
  }

  // ══════════════════════════════════════════════════════
  //  Chat API プロキシ (OpenAI)
  // ══════════════════════════════════════════════════════
  Future<void> _handleChatProxy(HttpRequest request) async {
    try {
      final body = await _readRequestBody(request);

      debugPrint('Chat proxy: key=${_openaiApiKey.substring(0, 10)}..., body len=${body.length}');
      final resp = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openaiApiKey',
        },
        body: body,
      ).timeout(const Duration(seconds: 60));
      debugPrint('Chat proxy resp: ${resp.statusCode}');

      request.response
        ..statusCode = resp.statusCode
        ..headers.contentType = ContentType.json
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..add(resp.bodyBytes);
      await request.response.close();
    } catch (e) {
      final err = utf8.encode(jsonEncode({'error': e.toString()}));
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..add(err);
      await request.response.close();
    }
  }

  // ══════════════════════════════════════════════════════
  //  TTS API プロキシ (AivisCloud)
  // ══════════════════════════════════════════════════════
  Future<void> _handleTtsProxy(HttpRequest request) async {
    try {
      final body = await _readRequestBody(request);
      final data = jsonDecode(body) as Map<String, dynamic>;
      final text = (data['text'] as String? ?? '').trim();

      if (text.isEmpty) {
        request.response
          ..statusCode = 400
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..write('Empty text');
        await request.response.close();
        return;
      }

      // AivisCloud API
      debugPrint('TTS proxy: key=${_aivisApiKey.substring(0, 10)}..., text="${text.substring(0, text.length > 20 ? 20 : text.length)}"');
      final aivisBody = jsonEncode({
        'model_uuid': _aivisModelUuid,
        'speaker_uuid': 'b1ca560f-f212-4e67-ab7d-0a4f5afb75a8',
        'text': text,
        'speed': 1.0,
        'output_format': 'mp3',
      });

      final resp = await http.post(
        Uri.parse(_aivisApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_aivisApiKey',
        },
        body: aivisBody,
      ).timeout(Duration(seconds: _aivisTimeout));
      debugPrint('TTS proxy resp: ${resp.statusCode}, bytes: ${resp.bodyBytes.length}');

      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.parse('audio/mpeg')
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..headers.add('X-TTS-Source', 'AivisCloud')
          ..add(resp.bodyBytes);
        await request.response.close();
        return;
      }

      // AivisCloud失敗時：空のレスポンスを返す（JSが処理する）
      final err = utf8.encode(jsonEncode({'error': 'TTS failed'}));
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..add(err);
      await request.response.close();
    } catch (e) {
      final err = utf8.encode(jsonEncode({'error': e.toString()}));
      request.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..headers.add('Access-Control-Allow-Origin', '*')
        ..add(err);
      await request.response.close();
    }
  }

  Future<String> _readRequestBody(HttpRequest request) async {
    final body = await request.fold<List<int>>(
      <int>[],
      (prev, element) => prev..addAll(element),
    );
    return utf8.decode(body);
  }

  /// assets/webapp/ → 一時ディレクトリにファイルコピー
  Future<void> _copyAssetsToDir(String targetDir) async {
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestJson);

    final webappAssets = manifest.keys
        .where((key) => key.startsWith('assets/webapp/'))
        .toList();

    for (final assetPath in webappAssets) {
      final relativePath = assetPath.replaceFirst('assets/webapp/', '');
      final targetPath = '$targetDir/$relativePath';

      final lastSlash = targetPath.lastIndexOf('/');
      if (lastSlash > 0) {
        final dir = Directory(targetPath.substring(0, lastSlash));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      try {
        final data = await rootBundle.load(assetPath);
        await File(targetPath).writeAsBytes(data.buffer.asUint8List());
      } catch (e) {
        debugPrint('Asset copy failed: $assetPath -> $e');
      }
    }
  }

  void _initWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050810))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (error) {
          debugPrint('WebView error: ${error.description}');
        },
        onNavigationRequest: (request) => NavigationDecision.navigate,
      ))
      ..setOnConsoleMessage((msg) {
        debugPrint('JS: ${msg.message}');
      })
      ..enableZoom(false);

    controller.loadRequest(
      Uri.parse('http://127.0.0.1:$_localServerPort/index.html'),
    );

    setState(() => _controller = controller);
  }

  String _getMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'html' => 'text/html; charset=utf-8',
      'css'  => 'text/css; charset=utf-8',
      'js'   => 'application/javascript; charset=utf-8',
      'json' => 'application/json; charset=utf-8',
      'png'  => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif'  => 'image/gif',
      'webp' => 'image/webp',
      'svg'  => 'image/svg+xml',
      'mp3'  => 'audio/mpeg',
      'mp4'  => 'video/mp4',
      'wav'  => 'audio/wav',
      'moc3' => 'application/octet-stream',
      _      => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050810),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_controller != null && await _controller!.canGoBack()) {
            _controller!.goBack();
          }
        },
        child: SafeArea(
          top: true,
          bottom: true,
          child: Stack(
            children: [
              if (_controller != null)
                WebViewWidget(controller: _controller!),

            if (_isLoading)
              Container(
                color: const Color(0xFF050810),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: Color(0xFF00E5FF), strokeWidth: 2),
                      SizedBox(height: 16),
                      Text('LOADING...',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 14, letterSpacing: 4,
                          fontFamily: 'monospace',
                        )),
                    ],
                  ),
                ),
              ),

            if (_error != null)
              Container(
                color: const Color(0xFF050810),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            _localServer?.close(force: true);
                            _startLocalServerAndLoad();
                          },
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
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
