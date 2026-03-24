// lib/screens/chat_screen.dart
// 近未来サイバーパンク × ラノベ風チャット画面

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../services/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/live2d_viewer_widget.dart';
import '../widgets/ornament_border.dart';
import 'situation_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey<Live2DViewerWidgetState> _live2dKey =
      GlobalKey<Live2DViewerWidgetState>();

  bool _showSituationPanel = false;
  late AnimationController _dialogAnimCtrl;

  @override
  void initState() {
    super.initState();
    _dialogAnimCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450),
    )..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupProvider());
  }

  void _setupProvider() {
    final p = context.read<ChatProvider>();
    p.onSetExpression = (e) => _live2dKey.currentState?.setExpression(e);
    p.onPlayMotion    = (m) => _live2dKey.currentState?.playMotion(m);
    p.onSetAffection  = (l) => _live2dKey.currentState?.setAffection(l);
  }

  @override
  void dispose() {
    _textCtrl.dispose(); _scrollCtrl.dispose();
    _dialogAnimCtrl.dispose(); super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    _dialogAnimCtrl.reset(); _dialogAnimCtrl.forward();
    await context.read<ChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  // ─── カラーマップ ───
  Color _emotionColor(EmotionType e) {
    switch (e) {
      case EmotionType.happy:     return AppTheme.neonGold;
      case EmotionType.love:      return AppTheme.neonPink;
      case EmotionType.shy:       return AppTheme.neonPink;
      case EmotionType.sad:       return AppTheme.neonCyan;
      case EmotionType.surprised: return AppTheme.neonGreen;
      case EmotionType.angry:     return const Color(0xFFFF4444);
      default:                    return AppTheme.neonPurple;
    }
  }

  String _emotionEmoji(EmotionType e) {
    switch (e) {
      case EmotionType.happy:     return '😊';
      case EmotionType.shy:       return '😳';
      case EmotionType.sad:       return '😢';
      case EmotionType.surprised: return '😲';
      case EmotionType.angry:     return '😠';
      case EmotionType.love:      return '😍';
      default:                    return '😌';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(
            child: Stack(children: [
              Column(children: [
                Expanded(flex: 58, child: _buildCharacterArea()),
                Expanded(flex: 42, child: _buildDialogArea()),
              ]),
              if (_showSituationPanel) _buildSituationOverlay(),
            ]),
          ),
          _buildInputArea(),
        ]),
      ),
    );
  }

  // ─── トップバー ───
  Widget _buildTopBar() {
    return Consumer<ChatProvider>(builder: (_, provider, __) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgMid,
          border: Border(bottom: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.2), width: 0.5)),
        ),
        child: Row(children: [
          // ── シチュエーションボタン ──
          GestureDetector(
            onTap: () => setState(() => _showSituationPanel = !_showSituationPanel),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _showSituationPanel
                    ? AppTheme.neonCyan.withValues(alpha: 0.8)
                    : AppTheme.borderDim,
                  width: 0.8,
                ),
                boxShadow: _showSituationPanel ? [
                  BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.2), blurRadius: 8)
                ] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(provider.situation.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(provider.situation.title,
                  style: TextStyle(
                    color: _showSituationPanel ? AppTheme.neonCyan : AppTheme.textSecond,
                    fontSize: 11, letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  _showSituationPanel ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 13,
                  color: _showSituationPanel ? AppTheme.neonCyan : AppTheme.textDim,
                ),
              ]),
            ),
          ),

          const Spacer(),

          // ── タイトル ──
          Text('VTUBER CHAT',
            style: TextStyle(
              color: AppTheme.neonCyan.withValues(alpha: 0.7),
              fontSize: 10, letterSpacing: 3,
            ),
          ),

          const Spacer(),

          // ── 好感度バー ──
          AffectionBar(level: provider.affectionLevel),

          const SizedBox(width: 8),

          // ── 設定ボタン ──
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.borderDim, width: 0.8),
              ),
              child: Icon(
                Icons.settings_outlined,
                color: AppTheme.textDim, size: 16,
              ),
            ),
          ),
        ]),
      );
    });
  }

  // ─── キャラクターエリア ───
  Widget _buildCharacterArea() {
    return Stack(children: [
      // 背景：深い宇宙感
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF060A14), Color(0xFF0A0F1E), Color(0xFF060A14)],
          ),
        ),
      ),

      // Live2D
      Live2DViewerWidget(
        key: _live2dKey,
        onControllerReady: (_) => _setupProvider(),
      ),

      // 上部ステータスHUD
      Positioned(top: 8, left: 12, right: 12,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _hudTag('LIVE2D', AppTheme.neonGreen),
            _hudTag('AI ONLINE', AppTheme.neonCyan),
          ],
        ),
      ),

      // 下部：キャラ名プレート
      Positioned(bottom: 10, left: 0, right: 0,
        child: Center(
          child: CharacterNamePlate(
            name: 'HIYORI',
            subtitle: context.watch<ChatProvider>().situation.title.toUpperCase(),
          ),
        ),
      ),
    ]);
  }

  Widget _hudTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.bgPanel.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 5)],
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 9, letterSpacing: 1.5)),
      ]),
    );
  }

  // ─── セリフ・チャットエリア ───
  Widget _buildDialogArea() {
    return Consumer<ChatProvider>(builder: (_, provider, __) {
      final msgs = provider.messages;
      final lastChar = msgs.lastWhere(
        (m) => m.sender == MessageSender.character,
        orElse: () => ChatMessage(
          id: '', text: '', sender: MessageSender.character, timestamp: DateTime.now(),
        ),
      );

      return Container(
        decoration: BoxDecoration(
          color: AppTheme.bgMid,
          border: Border(top: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.15), width: 0.5)),
        ),
        child: Column(children: [
          // ── メインホログラムダイアログ ──
          if (lastChar.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: HologramDialog(
                text: lastChar.text,
                characterName: 'HIYORI',
                emotionEmoji: _emotionEmoji(lastChar.emotion),
                accentColor: _emotionColor(lastChar.emotion),
              ),
            ),

          // ── チャット履歴 ──
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: msgs.length,
              itemBuilder: (_, i) => _buildBubble(msgs[i]),
            ),
          ),

          // ── ローディング ──
          if (provider.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _dotLoader(),
                const SizedBox(width: 10),
                Text('PROCESSING...',
                  style: TextStyle(
                    color: AppTheme.neonCyan.withValues(alpha: 0.6),
                    fontSize: 10, letterSpacing: 2,
                  ),
                ),
              ]),
            ),

          // ── エラー ──
          if (provider.errorMessage != null)
            _buildError(provider),
        ]),
      );
    });
  }

  Widget _dotLoader() {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 1.0),
        duration: Duration(milliseconds: 400 + i * 150),
        builder: (_, v, __) => Container(
          width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.neonCyan.withValues(alpha: v),
            boxShadow: [BoxShadow(color: AppTheme.neonCyan.withValues(alpha: v * 0.5), blurRadius: 6)],
          ),
        ),
      );
    }));
  }

  Widget _buildError(ChatProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0A0A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFF4444).withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(children: [
        const Text('⚠', style: TextStyle(color: Color(0xFFFF4444), fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(child: Text(provider.errorMessage!,
          style: const TextStyle(color: Color(0xFFFF8888), fontSize: 12))),
        GestureDetector(
          onTap: provider.clearError,
          child: const Icon(Icons.close, size: 14, color: Color(0xFFFF4444)),
        ),
      ]),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.sender == MessageSender.user;
    if (!isUser) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12), topRight: Radius.circular(3),
              bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12),
            ),
            border: Border.all(color: AppTheme.neonPurple.withValues(alpha: 0.35), width: 0.8),
            boxShadow: [BoxShadow(color: AppTheme.neonPurple.withValues(alpha: 0.12), blurRadius: 8)],
          ),
          child: Text(msg.text,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5, height: 1.5)),
        ),
      ]),
    );
  }

  // ─── 入力エリア ───
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgMid,
        border: Border(top: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.15), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '${context.watch<ChatProvider>().situation.emoji}  メッセージを入力…',
              hintStyle: TextStyle(color: AppTheme.textDim, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Consumer<ChatProvider>(builder: (_, p, __) {
          return GestureDetector(
            onTap: p.isLoading ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: p.isLoading ? AppTheme.bgCard : AppTheme.bgPanel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: p.isLoading
                    ? AppTheme.borderDim
                    : AppTheme.neonCyan.withValues(alpha: 0.6),
                  width: 1.0,
                ),
                boxShadow: p.isLoading ? null : [
                  BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.2), blurRadius: 10),
                ],
              ),
              child: Icon(Icons.send_rounded,
                color: p.isLoading ? AppTheme.textDim : AppTheme.neonCyan,
                size: 20,
              ),
            ),
          );
        }),
      ]),
    );
  }

  // ─── シチュエーション選択オーバーレイ ───
  Widget _buildSituationOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showSituationPanel = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgMid,
                  border: Border(
                    bottom: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.3), width: 0.8),
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Container(width: 3, height: 14, color: AppTheme.neonCyan,
                      margin: const EdgeInsets.only(right: 8)),
                    Text('SITUATION SELECT',
                      style: TextStyle(
                        color: AppTheme.neonCyan, fontSize: 11, letterSpacing: 2,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: kSituations.map((s) {
                      final isSelected = context.watch<ChatProvider>().situation.id == s.id;
                      return GestureDetector(
                        onTap: () {
                          context.read<ChatProvider>().setSituation(s);
                          setState(() => _showSituationPanel = false);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                              ? AppTheme.neonCyan.withValues(alpha: 0.12)
                              : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                ? AppTheme.neonCyan.withValues(alpha: 0.7)
                                : AppTheme.borderDim,
                              width: isSelected ? 1.0 : 0.7,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(color: AppTheme.neonCyan.withValues(alpha: 0.15), blurRadius: 8)
                            ] : null,
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(s.emoji, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 7),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.title,
                                style: TextStyle(
                                  color: isSelected ? AppTheme.neonCyan : AppTheme.textPrimary,
                                  fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(s.subtitle,
                                style: const TextStyle(color: AppTheme.textDim, fontSize: 9, letterSpacing: 0.5)),
                            ]),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
