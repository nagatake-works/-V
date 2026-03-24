// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'services/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/consent_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // 初回起動かどうか確認
  final prefs = await SharedPreferences.getInstance();
  final hasConsented = prefs.getBool('consent_agreed') ?? false;

  runApp(VtuberChatApp(hasConsented: hasConsented));
}

class VtuberChatApp extends StatelessWidget {
  final bool hasConsented;
  const VtuberChatApp({super.key, required this.hasConsented});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        title: 'Vtuber Chat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: hasConsented ? const SplashScreen() : const ConsentScreen(),
      ),
    );
  }
}

// ─── 近未来スプラッシュスクリーン ───
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainCtrl;
  late AnimationController _scanCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _scanAnim;
  int _bootLine = 0;
  final List<String> _bootLogs = [
    '> SYSTEM BOOT.............. OK',
    '> LOADING AI MODULE........ OK',
    '> CONNECTING LIVE2D........ OK',
    '> HIYORI ONLINE............ ✓',
  ];

  @override
  void initState() {
    super.initState();
    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _fadeAnim  = CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0)
      .animate(CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOutBack));
    _scanAnim  = _scanCtrl;

    // ブートログを順番に表示
    for (int i = 0; i < _bootLogs.length; i++) {
      Future.delayed(Duration(milliseconds: 600 + i * 350), () {
        if (mounted) setState(() => _bootLine = i + 1);
      });
    }

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ChatScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _mainCtrl.dispose(); _scanCtrl.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Stack(children: [
        // グリッドパターン
        CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _GridPainter(),
        ),

        // スキャンライン
        AnimatedBuilder(
          animation: _scanAnim,
          builder: (_, __) {
            final H = MediaQuery.of(context).size.height;
            final y = _scanAnim.value * H;
            return Positioned(
              top: y - 1, left: 0, right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    AppTheme.neonCyan.withValues(alpha: 0.4),
                    Colors.transparent,
                  ]),
                ),
              ),
            );
          },
        ),

        Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ロゴ枠
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.5), width: 1),
                    boxShadow: [
                      BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.15), blurRadius: 30),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // アプリ名
                    Text('VTUBER', style: TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 36, fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      shadows: [Shadow(color: AppTheme.neonCyan.withValues(alpha: 0.5), blurRadius: 20)],
                    )),
                    Text('C H A T', style: TextStyle(
                      color: AppTheme.neonPurple,
                      fontSize: 20, fontWeight: FontWeight.w300,
                      letterSpacing: 12,
                      shadows: [Shadow(color: AppTheme.neonPurple.withValues(alpha: 0.5), blurRadius: 15)],
                    )),
                    const SizedBox(height: 4),
                    Container(height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.transparent, AppTheme.neonCyan, Colors.transparent,
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('ひよりとの物語',
                      style: TextStyle(
                        color: AppTheme.textSecond, fontSize: 12, letterSpacing: 3,
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 32),

                // ブートログ
                Container(
                  width: 260,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgMid.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.borderDim, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(_bootLogs.length, (i) {
                      final visible = i < _bootLine;
                      return AnimatedOpacity(
                        opacity: visible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(_bootLogs[i],
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: i == _bootLogs.length - 1 && visible
                                  ? AppTheme.neonGreen
                                  : AppTheme.textSecond,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0A1A2E).withValues(alpha: 0.6)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const step = 30.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(_GridPainter _) => false;
}
