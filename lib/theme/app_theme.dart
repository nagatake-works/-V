// lib/theme/app_theme.dart
// 近未来サイバーパンク × ラノベ融合テーマ

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── カラーパレット（ダーク×ホログラム） ───
  static const Color bgDeep       = Color(0xFF0A0E1A); // 最深部
  static const Color bgMid        = Color(0xFF0F1528); // 中間
  static const Color bgCard       = Color(0xFF141B35); // カード
  static const Color bgPanel      = Color(0xFF1A2240); // パネル

  static const Color neonCyan     = Color(0xFF00E5FF); // シアン
  static const Color neonPurple   = Color(0xFFBB86FC); // パープル
  static const Color neonPink     = Color(0xFFFF4FC0); // ピンク
  static const Color neonGold     = Color(0xFFFFD700); // ゴールド
  static const Color neonGreen    = Color(0xFF00FF9F); // グリーン

  static const Color textPrimary  = Color(0xFFE8F4FF); // メインテキスト
  static const Color textSecond   = Color(0xFF8BAFD4); // サブテキスト
  static const Color textDim      = Color(0xFF4A6B8A); // 薄いテキスト

  static const Color borderGlow   = Color(0xFF00E5FF); // グローボーダー
  static const Color borderDim    = Color(0xFF1E3A5F); // 薄いボーダー

  static const Color userBubble   = Color(0xFF1E1245); // ユーザー吹き出し
  static const Color charBubble   = Color(0xFF0D2035); // キャラ吹き出し

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      surface: bgDeep,
      primary: neonCyan,
      secondary: neonPurple,
      onPrimary: bgDeep,
      onSurface: textPrimary,
    ),
    scaffoldBackgroundColor: bgDeep,
    textTheme: GoogleFonts.notoSansJpTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge: GoogleFonts.notoSansJp(
        color: textPrimary, fontSize: 15, height: 1.7,
      ),
      bodyMedium: GoogleFonts.notoSansJp(
        color: textPrimary, fontSize: 14, height: 1.6,
      ),
      titleLarge: GoogleFonts.notoSansJp(
        color: neonCyan, fontSize: 18, fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      labelSmall: GoogleFonts.notoSansJp(
        color: textDim, fontSize: 11,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.notoSansJp(
        color: neonCyan, fontSize: 16, fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
      iconTheme: const IconThemeData(color: neonCyan),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderDim),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderDim, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: neonCyan, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: GoogleFonts.notoSansJp(color: textDim, fontSize: 14),
    ),
  );
}
