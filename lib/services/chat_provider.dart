// lib/services/chat_provider.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import 'openai_service.dart';

class ChatProvider extends ChangeNotifier {
  final OpenAIService _ai = OpenAIService();

  final List<ChatMessage> _messages = [];
  SituationMode _situation = kSituations[0];
  bool _isLoading = false;
  String? _errorMessage;
  int _affectionLevel = 50;
  String _currentExpression = 'neutral';

  // WebView制御コールバック
  Function(String expression)? onSetExpression;
  Function(String motion)? onPlayMotion;
  Function(int level)? onSetAffection;

  List<ChatMessage> get messages => _messages;
  SituationMode get situation => _situation;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get affectionLevel => _affectionLevel;
  String get currentExpression => _currentExpression;

  ChatProvider() {
    _loadAffection();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      id: 'welcome',
      text: 'こんにちは！今日もよろしくね♪ 何か話したいことある…？',
      sender: MessageSender.character,
      emotion: EmotionType.happy,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _loadAffection() async {
    final prefs = await SharedPreferences.getInstance();
    _affectionLevel = prefs.getInt('affection_level') ?? 50;
    notifyListeners();
  }

  Future<void> _saveAffection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('affection_level', _affectionLevel);
  }

  void setSituation(SituationMode mode) {
    _situation = mode;
    _messages.clear();
    _messages.add(ChatMessage(
      id: 'situation_${mode.id}',
      text: _getSituationGreeting(mode),
      sender: MessageSender.character,
      emotion: EmotionType.happy,
      timestamp: DateTime.now(),
    ));
    _triggerExpression('happy', 'bounce');
    notifyListeners();
  }

  String _getSituationGreeting(SituationMode mode) {
    switch (mode.id) {
      case 'date_park':
        return '桜がきれいだね…♪ こうして一緒に来れて嬉しいよ。';
      case 'date_cafe':
        return 'ここのケーキ、美味しそう！一緒に選ぼう？';
      case 'date_evening':
        return '夕日、すごくきれい…。ねえ、このまましばらく一緒にいていい？';
      case 'festival':
        return 'わあ、すごい人！浴衣、似合ってるって言ってくれると嬉しいな…♡';
      case 'rainy':
        return 'あ、雨降ってきちゃった…。よかったら一緒に入る？';
      default:
        return 'ねえ、今日は何の話しようか♪';
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _errorMessage = null;
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      sender: MessageSender.user,
      emotion: EmotionType.neutral,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _ai.chat(
        history: _messages,
        userMessage: text,
        situation: _situation,
        affectionLevel: _affectionLevel,
      );

      // 好感度更新
      _affectionLevel = (_affectionLevel + response.affectionDelta).clamp(0, 100);
      await _saveAffection();

      // Live2D 制御
      _triggerExpression(response.expression, response.motion);

      final charMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: response.text,
        sender: MessageSender.character,
        emotion: response.emotion,
        timestamp: DateTime.now(),
      );
      _messages.add(charMsg);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('quota') || errStr.contains('insufficient')) {
        _errorMessage = 'APIクレジットが切れています。オフラインモードで動作中。';
      } else if (errStr.contains('Timeout') || errStr.contains('Socket')) {
        _errorMessage = 'ネットワーク接続を確認してください。';
      } else {
        _errorMessage = 'エラーが発生しました。もう一度試してね。';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _triggerExpression(String expression, String motion) {
    _currentExpression = expression;
    onSetExpression?.call(expression);
    onPlayMotion?.call(motion);
    onSetAffection?.call(_affectionLevel);
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
