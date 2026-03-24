// lib/screens/consent_screen.dart
// 初回起動時の利用規約・プライバシーポリシー同意画面（世界観版）

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen>
    with SingleTickerProviderStateMixin {
  bool _agreedTerms   = false;
  bool _agreedPrivacy = false;
  bool _isOver13      = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  bool get _canProceed => _agreedTerms && _agreedPrivacy && _isOver13;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAgree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_agreed', true);
    await prefs.setString('consent_date', DateTime.now().toIso8601String());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const ChatScreen(),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFD6F0),
              Color(0xFFE8B4F8),
              Color(0xFFC9A8F5),
              Color(0xFFA8C8FF),
              Color(0xFFD4F0FF),
            ],
            stops: [0.0, 0.2, 0.45, 0.75, 1.0],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SafeArea(
            child: Column(
              children: [
                // ── ヘッダー ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Column(
                    children: [
                      // ロゴ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD090FF).withValues(alpha: 0.25),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              '君とV',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 4,
                                foreground: Paint()
                                  ..shader = const LinearGradient(
                                    colors: [Color(0xFFE060C0), Color(0xFF8060E8), Color(0xFF60A0FF)],
                                  ).createShader(const Rect.fromLTWH(0, 0, 200, 40)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'はじめにご確認ください',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF7040A0).withValues(alpha: 0.7),
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── スクロール内容 ──
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSection(
                          emoji: '💬',
                          color: const Color(0xFFE080C0),
                          title: 'このアプリについて',
                          content:
                              'AI（ChatGPT）を使ったVtuberチャットアプリです。\n\n'
                              '• AIの返答はフィクションです\n'
                              '• 個人情報を入力しないでください\n'
                              '• 13歳未満の方はご利用いただけません\n'
                              '• 過度な依存にはご注意ください',
                        ),
                        const SizedBox(height: 12),
                        _buildSection(
                          emoji: '🔒',
                          color: const Color(0xFF8060E8),
                          title: 'プライバシーポリシー',
                          content:
                              '• メッセージはOpenAI APIに送信されます\n'
                              '• アプリ内データはデバイスにのみ保存されます\n'
                              '• 広告・アナリティクスSDKは含まれません',
                          linkText: '全文を読む',
                          onLinkTap: () => _showFullText(context, _privacyPolicy, 'プライバシーポリシー'),
                        ),
                        const SizedBox(height: 12),
                        _buildSection(
                          emoji: '📋',
                          color: const Color(0xFF60A0E8),
                          title: '利用規約',
                          content:
                              '• 商用目的での無断利用は禁止します\n'
                              '• 違法・有害なコンテンツの生成を試みないでください\n'
                              '• サービスは予告なく変更・終了する場合があります',
                          linkText: '全文を読む',
                          onLinkTap: () => _showFullText(context, _terms, '利用規約'),
                        ),
                        const SizedBox(height: 24),

                        // ── チェックボックス ──
                        _buildCheckbox(
                          value: _isOver13,
                          label: '私は13歳以上です',
                          color: const Color(0xFFE080C0),
                          onChanged: (v) => setState(() => _isOver13 = v!),
                        ),
                        const SizedBox(height: 10),
                        _buildCheckbox(
                          value: _agreedPrivacy,
                          label: 'プライバシーポリシーに同意します',
                          color: const Color(0xFF8060E8),
                          onChanged: (v) => setState(() => _agreedPrivacy = v!),
                        ),
                        const SizedBox(height: 10),
                        _buildCheckbox(
                          value: _agreedTerms,
                          label: '利用規約に同意します',
                          color: const Color(0xFF60A0E8),
                          onChanged: (v) => setState(() => _agreedTerms = v!),
                        ),
                        const SizedBox(height: 28),

                        // ── 同意ボタン ──
                        AnimatedScale(
                          scale: _canProceed ? 1.0 : 0.97,
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedOpacity(
                            opacity: _canProceed ? 1.0 : 0.45,
                            duration: const Duration(milliseconds: 300),
                            child: SizedBox(
                              width: double.infinity,
                              child: GestureDetector(
                                onTap: _canProceed ? _onAgree : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFE070C8), Color(0xFF9060E0), Color(0xFF60A0FF)],
                                    ),
                                    borderRadius: BorderRadius.circular(50),
                                    boxShadow: _canProceed ? [
                                      BoxShadow(
                                        color: const Color(0xFFB060E0).withValues(alpha: 0.45),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ] : [],
                                  ),
                                  child: const Text(
                                    '同意してはじめる  ✨',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String emoji,
    required Color color,
    required String title,
    required String content,
    String? linkText,
    VoidCallback? onLinkTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13,
            )),
          ]),
          const SizedBox(height: 10),
          Text(content, style: TextStyle(
            color: const Color(0xFF4A3060).withValues(alpha: 0.8),
            fontSize: 12, height: 1.75,
          )),
          if (linkText != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onLinkTap,
              child: Text(
                linkText,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckbox({
    required bool value,
    required String label,
    required Color color,
    required ValueChanged<bool?> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: value ? color : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
                boxShadow: value ? [
                  BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
                ] : [],
              ),
              child: value
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(
              color: const Color(0xFF4A3060).withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: value ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  void _showFullText(BuildContext context, String text, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5E8FF), Color(0xFFE8F0FF)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFB080D0).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(title, style: const TextStyle(
                  color: Color(0xFF6040A0),
                  fontWeight: FontWeight.bold, fontSize: 16,
                )),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.all(20),
                  child: Text(text, style: const TextStyle(
                    color: Color(0xFF4A3060), fontSize: 12, height: 1.9,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── プライバシーポリシー全文 ───
const _privacyPolicy = '''
プライバシーポリシー

最終更新日：2025年1月1日

1. 収集する情報
本アプリは以下の情報を収集します：
・チャット入力内容（OpenAI API処理のため）
・アプリ内設定データ（デバイスローカルに保存）

2. 情報の利用方法
収集した情報は以下の目的にのみ使用します：
・AIによる会話応答の生成
・アプリ設定の保持

3. 第三者への情報提供
・OpenAI LLC：チャット内容の処理のため
  （OpenAI プライバシーポリシー：https://openai.com/privacy）
・上記以外の第三者への販売・提供は行いません

4. データの保管
・チャット履歴はサーバーに保存されません
・好感度・設定データはデバイスにのみ保存されます

5. お子様のプライバシー
本サービスは13歳未満のお子様を対象としていません。

6. ポリシーの変更
本ポリシーを変更する場合、アプリ内でお知らせします。

7. お問い合わせ
ご質問はアプリ内設定画面よりお問い合わせください。
''';

// ─── 利用規約全文 ───
const _terms = '''
利用規約

最終更新日：2025年1月1日

第1条（適用）
本規約は本アプリの利用に関する条件を定めるものです。

第2条（利用条件）
・13歳以上の方のみご利用いただけます
・本規約に同意した場合のみご利用いただけます

第3条（禁止事項）
以下の行為を禁止します：
・違法または有害なコンテンツの生成を試みる行為
・他者への迷惑行為
・商用目的での無断利用
・リバースエンジニアリング

第4条（免責事項）
・AIの返答はフィクションであり保証しません
・サービスの中断・終了について責任を負いません
・AI生成コンテンツの正確性を保証しません

第5条（サービスの変更・終了）
予告なくサービスを変更・終了する場合があります。

第6条（準拠法）
本規約は日本法に準拠します。
''';
