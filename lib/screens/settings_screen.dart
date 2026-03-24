// lib/screens/settings_screen.dart
// アプリ設定画面

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/chat_provider.dart';
import 'consent_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bgmEnabled = true;
  bool _voiceEnabled = true;
  double _bgmVolume = 0.7;
  double _seVolume = 0.8;

  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '1';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bgmEnabled = prefs.getBool('bgm_enabled') ?? true;
      _voiceEnabled = prefs.getBool('voice_enabled') ?? true;
      _bgmVolume = prefs.getDouble('bgm_volume') ?? 0.7;
      _seVolume = prefs.getDouble('se_volume') ?? 0.8;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bgm_enabled', _bgmEnabled);
    await prefs.setBool('voice_enabled', _voiceEnabled);
    await prefs.setDouble('bgm_volume', _bgmVolume);
    await prefs.setDouble('se_volume', _seVolume);
  }

  Future<void> _confirmResetAffection() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1225),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
        ),
        title: Text('好感度をリセット',
          style: TextStyle(color: AppTheme.neonCyan, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'ひよりとの好感度を50にリセットします。\nよろしいですか？',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('キャンセル', style: TextStyle(color: AppTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('リセット', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('affection_level', 50);
      // Web向け: localStorageにリセットフラグを書き込む
      await prefs.setString('affection', '50');
      await prefs.setBool('affection_reset', true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('好感度をリセットしました'),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmResetConsent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1225),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
        ),
        title: Text('同意をリセット',
          style: TextStyle(color: AppTheme.neonCyan, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          '利用規約・プライバシーポリシーの同意をリセットします。\n次回起動時に同意画面が表示されます。',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('キャンセル', style: TextStyle(color: AppTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('リセット', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('consent_agreed');
      await prefs.remove('consent_date');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConsentScreen()),
        (_) => false,
      );
    }
  }

  void _showPrivacyPolicy() {
    _showFullText(context, _privacyPolicyText, 'プライバシーポリシー');
  }

  void _showTerms() {
    _showFullText(context, _termsText, '利用規約');
  }

  void _showFullText(BuildContext ctx, String text, String title) {
    showModalBottomSheet(
      context: ctx,
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
                color: Colors.white30, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(title, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                child: Text(text, style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final affection = context.watch<ChatProvider>().affectionLevel;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgMid,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppTheme.neonCyan, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(children: [
          Container(width: 3, height: 16, color: AppTheme.neonCyan,
            margin: const EdgeInsets.only(right: 10)),
          Text('SETTINGS',
            style: TextStyle(
              color: AppTheme.neonCyan, fontSize: 14,
              fontWeight: FontWeight.w700, letterSpacing: 3)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 0.5,
            color: AppTheme.neonCyan.withValues(alpha: 0.2),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── サウンド設定 ──
          _buildSectionHeader('🔊  サウンド設定'),
          _buildCard(children: [
            _buildSwitchTile(
              icon: Icons.music_note_rounded,
              label: 'BGM',
              value: _bgmEnabled,
              onChanged: (v) {
                setState(() => _bgmEnabled = v);
                _saveSettings();
              },
            ),
            _buildDivider(),
            _buildSliderTile(
              icon: Icons.volume_up_rounded,
              label: 'BGM音量',
              value: _bgmVolume,
              enabled: _bgmEnabled,
              onChanged: (v) {
                setState(() => _bgmVolume = v);
                _saveSettings();
              },
            ),
            _buildDivider(),
            _buildSwitchTile(
              icon: Icons.record_voice_over_rounded,
              label: 'ボイス',
              value: _voiceEnabled,
              onChanged: (v) {
                setState(() => _voiceEnabled = v);
                _saveSettings();
              },
            ),
            _buildDivider(),
            _buildSliderTile(
              icon: Icons.graphic_eq_rounded,
              label: '効果音量',
              value: _seVolume,
              enabled: true,
              onChanged: (v) {
                setState(() => _seVolume = v);
                _saveSettings();
              },
            ),
          ]),

          const SizedBox(height: 16),

          // ── 好感度 ──
          _buildSectionHeader('💖  好感度'),
          _buildCard(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Icon(Icons.favorite_rounded, color: AppTheme.neonPink, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('現在の好感度',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: affection / 100.0,
                          backgroundColor: AppTheme.bgPanel,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            affection >= 70 ? AppTheme.neonPink
                            : affection >= 40 ? AppTheme.neonGold
                            : AppTheme.neonCyan,
                          ),
                          minHeight: 8,
                        ),
                      )),
                      const SizedBox(width: 12),
                      Text('$affection',
                        style: TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 16, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                )),
              ]),
            ),
            _buildDivider(),
            _buildActionTile(
              icon: Icons.restart_alt_rounded,
              label: '好感度をリセット',
              color: Colors.redAccent,
              onTap: _confirmResetAffection,
            ),
          ]),

          const SizedBox(height: 16),

          // ── 法的情報 ──
          _buildSectionHeader('📋  法的情報'),
          _buildCard(children: [
            _buildActionTile(
              icon: Icons.privacy_tip_outlined,
              label: 'プライバシーポリシー',
              color: AppTheme.neonCyan,
              onTap: _showPrivacyPolicy,
              trailing: Icon(Icons.chevron_right, color: AppTheme.textDim, size: 18),
            ),
            _buildDivider(),
            _buildActionTile(
              icon: Icons.article_outlined,
              label: '利用規約',
              color: AppTheme.neonPurple,
              onTap: _showTerms,
              trailing: Icon(Icons.chevron_right, color: AppTheme.textDim, size: 18),
            ),
            _buildDivider(),
            _buildActionTile(
              icon: Icons.refresh_rounded,
              label: '同意をリセットして再確認',
              color: Colors.orangeAccent,
              onTap: _confirmResetConsent,
            ),
          ]),

          const SizedBox(height: 16),

          // ── アプリ情報 ──
          _buildSectionHeader('ℹ️  アプリ情報'),
          _buildCard(children: [
            _buildInfoTile('アプリ名', 'Vtuber Chat'),
            _buildDivider(),
            _buildInfoTile('バージョン', '$_appVersion ($_buildNumber)'),
            _buildDivider(),
            _buildInfoTile('キャラクター', '来鳥アルエ'),
            _buildDivider(),
            _buildInfoTile('AI', 'GPT-4o (OpenAI)'),
            _buildDivider(),
            _buildInfoTile('Live2D SDK', 'Cubism SDK 4'),
            if (kDebugMode) ...[
              _buildDivider(),
              _buildInfoTile('モード', 'DEBUG'),
            ],
          ]),

          const SizedBox(height: 32),

          // フッター
          Center(
            child: Text(
              '© 2025 Vtuber Chat\nAll rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 11, height: 1.8),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title,
        style: TextStyle(
          color: AppTheme.textSecond, fontSize: 12, fontWeight: FontWeight.w600,
          letterSpacing: 1.5)),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.06), indent: 48);
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppTheme.neonCyan, size: 20),
      title: Text(label,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      trailing: Transform.scale(
        scale: 0.85,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.neonCyan,
          activeTrackColor: AppTheme.neonCyan.withValues(alpha: 0.4),
          inactiveThumbColor: AppTheme.textDim,
          inactiveTrackColor: AppTheme.bgPanel,
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required IconData icon,
    required String label,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Icon(icon, color: enabled ? AppTheme.neonCyan : AppTheme.textDim, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(
              color: enabled ? AppTheme.textPrimary : AppTheme.textDim,
              fontSize: 13)),
            const Spacer(),
            Text('${(value * 100).toInt()}%',
              style: TextStyle(
                color: enabled ? AppTheme.neonCyan : AppTheme.textDim,
                fontSize: 11)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: enabled ? AppTheme.neonCyan : AppTheme.textDim,
              inactiveTrackColor: AppTheme.bgPanel,
              thumbColor: enabled ? AppTheme.neonCyan : AppTheme.textDim,
              overlayColor: AppTheme.neonCyan.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ])),
      ]),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label, style: TextStyle(color: AppTheme.textSecond, fontSize: 12)),
      trailing: Text(value,
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }
}

// ── プライバシーポリシー全文 ──
const _privacyPolicyText = '''
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

// ── 利用規約全文 ──
const _termsText = '''
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
