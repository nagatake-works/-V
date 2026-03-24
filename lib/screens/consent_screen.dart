// lib/screens/consent_screen.dart
// 初回起動時の利用規約・プライバシーポリシー同意画面

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreedTerms   = false;
  bool _agreedPrivacy = false;
  bool _isOver13      = false;

  bool get _canProceed => _agreedTerms && _agreedPrivacy && _isOver13;

  Future<void> _onAgree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('consent_agreed', true);
    await prefs.setString('consent_date', DateTime.now().toIso8601String());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'VTUBER CHAT',
                    style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      letterSpacing: 8, color: AppTheme.neonCyan,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'はじめにご確認ください',
                    style: TextStyle(
                      fontSize: 13, color: Colors.white70, letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // 内容スクロール
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      icon: Icons.warning_amber_rounded,
                      iconColor: Colors.orange,
                      title: 'ご利用にあたって',
                      content:
                          '本アプリはAI（ChatGPT）を使用したVtuberチャットアプリです。\n\n'
                          '• AIが生成する返答はフィクションです\n'
                          '• 個人情報を入力しないでください\n'
                          '• 13歳未満の方はご利用いただけません\n'
                          '• 過度な依存にはご注意ください',
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.lock_outline,
                      iconColor: AppTheme.neonCyan,
                      title: 'プライバシーポリシー（要約）',
                      content:
                          '• 送信されたメッセージはOpenAI APIに送信されます\n'
                          '• OpenAIのプライバシーポリシーが適用されます\n'
                          '• アプリ内データ（好感度等）はデバイスにのみ保存されます\n'
                          '• 広告・アナリティクスSDKは含まれません',
                      linkText: '全文を読む',
                      onLinkTap: () => _showFullText(context, _privacyPolicy, 'プライバシーポリシー'),
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.article_outlined,
                      iconColor: AppTheme.neonPurple,
                      title: '利用規約（要約）',
                      content:
                          '• 商用目的での無断利用は禁止します\n'
                          '• 違法・有害なコンテンツの生成を試みないでください\n'
                          '• サービスは予告なく変更・終了する場合があります',
                      linkText: '全文を読む',
                      onLinkTap: () => _showFullText(context, _terms, '利用規約'),
                    ),
                    const SizedBox(height: 28),

                    // チェックボックス群
                    _buildCheckbox(
                      value: _isOver13,
                      label: '私は13歳以上です',
                      onChanged: (v) => setState(() => _isOver13 = v!),
                    ),
                    const SizedBox(height: 8),
                    _buildCheckbox(
                      value: _agreedPrivacy,
                      label: 'プライバシーポリシーに同意します',
                      onChanged: (v) => setState(() => _agreedPrivacy = v!),
                    ),
                    const SizedBox(height: 8),
                    _buildCheckbox(
                      value: _agreedTerms,
                      label: '利用規約に同意します',
                      onChanged: (v) => setState(() => _agreedTerms = v!),
                    ),
                    const SizedBox(height: 32),

                    // 同意ボタン
                    SizedBox(
                      width: double.infinity,
                      child: AnimatedOpacity(
                        opacity: _canProceed ? 1.0 : 0.4,
                        duration: const Duration(milliseconds: 300),
                        child: ElevatedButton(
                          onPressed: _canProceed ? _onAgree : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.neonCyan,
                            foregroundColor: AppTheme.bgDeep,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            '同意してはじめる',
                            style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    String? linkText,
    VoidCallback? onLinkTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(
              color: iconColor, fontWeight: FontWeight.bold, fontSize: 13,
            )),
          ]),
          const SizedBox(height: 10),
          Text(content, style: const TextStyle(
            color: Colors.white70, fontSize: 12, height: 1.7,
          )),
          if (linkText != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onLinkTap,
              child: Text(
                linkText,
                style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.neonCyan,
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
    required ValueChanged<bool?> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: value ? AppTheme.neonCyan.withValues(alpha: 0.2) : Colors.transparent,
              border: Border.all(
                color: value ? AppTheme.neonCyan : Colors.white30,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: value
                ? Icon(Icons.check, size: 14, color: AppTheme.neonCyan)
                : null,
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  void _showFullText(BuildContext context, String text, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1225),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, sc) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(title, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16,
              )),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                child: Text(text, style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.8,
                )),
              ),
            ),
          ],
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
