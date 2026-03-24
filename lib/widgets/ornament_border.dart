// lib/widgets/ornament_border.dart
// 近未来サイバーUIウィジェット群

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─── サイバーボーダーボックス ───
class CyberBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? glowColor;
  final bool animated;

  const CyberBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.glowColor,
    this.animated = false,
  });

  @override
  Widget build(BuildContext context) {
    final gc = glowColor ?? AppTheme.neonCyan;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gc.withValues(alpha: 0.5), width: 1.0),
        boxShadow: [
          BoxShadow(color: gc.withValues(alpha: 0.18), blurRadius: 12, spreadRadius: 0),
          BoxShadow(color: gc.withValues(alpha: 0.06), blurRadius: 30, spreadRadius: 2),
        ],
      ),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          _cornerAccent(top: 0, left: 0),
          _cornerAccent(top: 0, right: 0, flipH: true),
          _cornerAccent(bottom: 0, left: 0, flipV: true),
          _cornerAccent(bottom: 0, right: 0, flipH: true, flipV: true),
        ],
      ),
    );
  }

  Widget _cornerAccent({
    double? top, double? bottom, double? left, double? right,
    bool flipH = false, bool flipV = false,
  }) {
    final gc = glowColor ?? AppTheme.neonCyan;
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Transform.scale(
        scaleX: flipH ? -1 : 1, scaleY: flipV ? -1 : 1,
        child: SizedBox(
          width: 14, height: 14,
          child: CustomPaint(painter: _CyberCornerPainter(color: gc)),
        ),
      ),
    );
  }
}

class _CyberCornerPainter extends CustomPainter {
  final Color color;
  const _CyberCornerPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(0, size.height), Offset(0, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
  }
  @override
  bool shouldRepaint(_CyberCornerPainter o) => o.color != color;
}

// ─── スキャンラインアニメーション付きボックス ───
class ScanlineBox extends StatefulWidget {
  final Widget child;
  final EdgeInsets padding;

  const ScanlineBox({super.key, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  State<ScanlineBox> createState() => _ScanlineBoxState();
}

class _ScanlineBoxState extends State<ScanlineBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _anim = _ctrl;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            child!,
            Positioned.fill(
              child: CustomPaint(
                painter: _ScanlinePainter(progress: _anim.value),
              ),
            ),
          ],
        ),
      ),
      child: CyberBox(padding: widget.padding, child: widget.child),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final double progress;
  const _ScanlinePainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final y = progress * size.height;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          AppTheme.neonCyan.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, y - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 60), paint);
  }
  @override
  bool shouldRepaint(_ScanlinePainter o) => o.progress != progress;
}

// ─── キャラクター名プレート（近未来版） ───
class CharacterNamePlate extends StatefulWidget {
  final String name;
  final String? subtitle;

  const CharacterNamePlate({super.key, required this.name, this.subtitle});

  @override
  State<CharacterNamePlate> createState() => _CharacterNamePlateState();
}

class _CharacterNamePlateState extends State<CharacterNamePlate>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.bgPanel.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppTheme.neonCyan.withValues(alpha: 0.4 + _pulse.value * 0.3),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.neonCyan.withValues(alpha: 0.15 + _pulse.value * 0.15),
              blurRadius: 16, spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ステータスドット
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.neonGreen,
                boxShadow: [BoxShadow(color: AppTheme.neonGreen.withValues(alpha: 0.6), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: AppTheme.neonCyan, fontSize: 14,
                    fontWeight: FontWeight.w600, letterSpacing: 3,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: TextStyle(
                      color: AppTheme.textDim, fontSize: 9, letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            // アクティブインジケーター
            Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => Container(
                width: 2, height: 4 + i * 2.0,
                margin: const EdgeInsets.only(bottom: 1),
                color: AppTheme.neonCyan.withValues(alpha: 0.3 + i * 0.25),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 好感度バー（近未来版） ───
class AffectionBar extends StatelessWidget {
  final int level;
  const AffectionBar({super.key, required this.level});

  String get _label {
    if (level >= 90) return 'FATED ♡♡♡';
    if (level >= 75) return 'LOVE ♡♡';
    if (level >= 60) return 'LIKE ♡';
    if (level >= 45) return 'INTEREST';
    if (level >= 30) return 'NEUTRAL';
    return 'STRANGER';
  }

  Color get _barColor {
    if (level >= 75) return const Color(0xFFFF4FC0);
    if (level >= 50) return AppTheme.neonPurple;
    return AppTheme.neonCyan;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderDim, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('♥', style: TextStyle(color: _barColor, fontSize: 10)),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(height: 5, color: AppTheme.borderDim),
                  FractionallySizedBox(
                    widthFactor: level / 100,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.neonCyan, _barColor],
                        ),
                        boxShadow: [
                          BoxShadow(color: _barColor.withValues(alpha: 0.5), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _label,
            style: TextStyle(color: _barColor, fontSize: 9, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

// ─── ホログラム吹き出し（キャラクターセリフ） ───
class HologramDialog extends StatefulWidget {
  final String text;
  final String characterName;
  final String emotionEmoji;
  final Color? accentColor;

  const HologramDialog({
    super.key,
    required this.text,
    required this.characterName,
    this.emotionEmoji = '😌',
    this.accentColor,
  });

  @override
  State<HologramDialog> createState() => _HologramDialogState();
}

class _HologramDialogState extends State<HologramDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: 8, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(HologramDialog old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _ctrl.reset();
      _ctrl.forward();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ac = widget.accentColor ?? AppTheme.neonPurple;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _slideAnim.value),
        child: Opacity(
          opacity: _fadeAnim.value,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ac.withValues(alpha: 0.45), width: 1.0),
              boxShadow: [
                BoxShadow(color: ac.withValues(alpha: 0.15), blurRadius: 16),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ヘッダー
                      Row(
                        children: [
                          Text(widget.emotionEmoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                          Text(
                            widget.characterName,
                            style: TextStyle(
                              color: ac, fontSize: 11,
                              fontWeight: FontWeight.w600, letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: ac.withValues(alpha: 0.4), width: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(color: ac, fontSize: 8, letterSpacing: 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // セリフ
                      Text(
                        widget.text,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14.5, height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                // 四隅装飾
                ..._corners(ac),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _corners(Color c) => [
    _c(c, top: 0, left: 0),
    _c(c, top: 0, right: 0, fH: true),
    _c(c, bottom: 0, left: 0, fV: true),
    _c(c, bottom: 0, right: 0, fH: true, fV: true),
  ];

  Widget _c(Color c, {double? top, double? bottom, double? left, double? right, bool fH=false, bool fV=false}) =>
    Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Transform.scale(scaleX: fH ? -1 : 1, scaleY: fV ? -1 : 1,
        child: SizedBox(width: 12, height: 12,
          child: CustomPaint(painter: _CyberCornerPainter(color: c)),
        ),
      ),
    );
}
