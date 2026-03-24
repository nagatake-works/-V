// lib/services/openai_service.dart
// プロキシ経由でOpenAI APIを呼び出す（CORS回避）

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class OpenAIService {
  // Web環境ではプロキシ経由、それ以外は直接呼び出し
  static String get _baseUrl {
    if (kIsWeb) {
      // 同一オリジンのプロキシエンドポイント
      return '/api/chat';
    }
    return 'https://api.openai.com/v1/chat/completions';
  }

  // APIキーは --dart-define=OPENAI_API_KEY=sk-xxx でビルド時に注入
  // リリースビルド: flutter build apk --dart-define=OPENAI_API_KEY=sk-xxx
  // デフォルト値は空文字列（リリース時は必ず--dart-defineで指定すること）
  static const String _apiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  static const Map<String, String> _emotionToExpression = {
    'happy': 'happy', 'joy': 'happy', 'excited': 'happy',
    'love': 'love', 'romantic': 'love',
    'shy': 'shy', 'embarrassed': 'shy', 'blush': 'shy',
    'sad': 'sad', 'lonely': 'sad', 'worried': 'sad',
    'surprised': 'surprised', 'shocked': 'surprised',
    'angry': 'angry', 'frustrated': 'angry',
    'neutral': 'neutral', 'calm': 'neutral',
  };

  static const Map<String, String> _emotionToMotion = {
    'happy': 'bounce', 'joy': 'bounce', 'excited': 'bounce',
    'love': 'nod', 'romantic': 'nod', 'shy': 'nod',
    'surprised': 'shake', 'angry': 'shake',
    'sad': 'idle', 'neutral': 'idle', 'calm': 'idle',
  };

  Future<AIResponse> chat({
    required List<ChatMessage> history,
    required String userMessage,
    required SituationMode situation,
    required int affectionLevel,
  }) async {
    // APIキーが未設定の場合はオフラインフォールバック
    if (!kIsWeb && _apiKey.isEmpty) {
      return _generateOfflineResponse(userMessage, situation, affectionLevel);
    }

    final messages = _buildMessages(
      history: history,
      userMessage: userMessage,
      situation: situation,
      affectionLevel: affectionLevel,
    );

    final requestBody = jsonEncode({
      'model': 'gpt-4o',
      'messages': messages,
      'max_tokens': 300,
      'temperature': 0.9,
      'response_format': {'type': 'json_object'},
    });

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      };
      // Webプロキシ経由の場合はAuthヘッダー不要（サーバー側で付加）
      if (!kIsWeb) {
        headers['Authorization'] = 'Bearer $_apiKey';
      }

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: headers,
            body: requestBody,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final content = decoded['choices'][0]['message']['content'] as String;
        return _parseResponse(content);
      } else {
        String errMsg = 'API Error ${response.statusCode}';
        try {
          final err = jsonDecode(response.body);
          final apiErrMsg = err['error']?['message'] as String? ?? '';
          errMsg = apiErrMsg.isNotEmpty ? apiErrMsg : errMsg;
          // クォータ超過の場合はフォールバックモードへ
          if (errMsg.contains('quota') || errMsg.contains('insufficient') ||
              response.statusCode == 429 || response.statusCode == 401) {
            return _generateOfflineResponse(userMessage, situation, affectionLevel);
          }
        } catch (_) {}
        throw Exception(errMsg);
      }
    } catch (e) {
      // ネットワークエラーやタイムアウトの場合もフォールバック
      if (e.toString().contains('quota') || e.toString().contains('insufficient') ||
          e.toString().contains('TimeoutException') || e.toString().contains('SocketException')) {
        return _generateOfflineResponse(userMessage, situation, affectionLevel);
      }
      rethrow;
    }
  }

  List<Map<String, String>> _buildMessages({
    required List<ChatMessage> history,
    required String userMessage,
    required SituationMode situation,
    required int affectionLevel,
  }) {
    final systemContent = '''
${situation.systemPrompt}

現在の好感度: $affectionLevel/100
好感度が高いほど甘く、恥ずかしがり屋になってください。

必ずJSON形式のみで返してください（説明文なし）:
{"text":"キャラクターのセリフ（日本語、1〜3文）","emotion":"happy/joy/love/romantic/shy/embarrassed/sad/surprised/angry/neutral のいずれか","affection_delta":整数(-5〜+10)}
''';

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': systemContent},
    ];

    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;
    for (final msg in recent) {
      msgs.add({
        'role': msg.sender == MessageSender.user ? 'user' : 'assistant',
        'content': msg.sender == MessageSender.user
            ? msg.text
            : jsonEncode({'text': msg.text, 'emotion': msg.emotion.name}),
      });
    }
    msgs.add({'role': 'user', 'content': userMessage});
    return msgs;
  }

  AIResponse _parseResponse(String content) {
    try {
      // JSONブロックを抽出（```json ... ``` の可能性も考慮）
      String jsonStr = content.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch != null) jsonStr = jsonMatch.group(0)!;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final text = json['text'] as String? ?? 'ごめん、うまく話せなかった…';
      final emotionKey = (json['emotion'] as String? ?? 'neutral').toLowerCase();
      final affectionDelta = (json['affection_delta'] as num?)?.toInt() ?? 0;

      final expression = _emotionToExpression[emotionKey] ?? 'neutral';
      final motion = _emotionToMotion[emotionKey] ?? 'idle';

      final emotionType = _toEmotionType(expression);
      return AIResponse(
        text: text, emotion: emotionType,
        expression: expression, motion: motion,
        affectionDelta: affectionDelta,
      );
    } catch (_) {
      return AIResponse(
        text: content.length > 200 ? content.substring(0, 200) : content,
        emotion: EmotionType.neutral,
        expression: 'neutral', motion: 'idle', affectionDelta: 0,
      );
    }
  }

  EmotionType _toEmotionType(String expression) {
    switch (expression) {
      case 'happy':     return EmotionType.happy;
      case 'shy':       return EmotionType.shy;
      case 'sad':       return EmotionType.sad;
      case 'surprised': return EmotionType.surprised;
      case 'angry':     return EmotionType.angry;
      case 'love':      return EmotionType.love;
      default:          return EmotionType.neutral;
    }
  }

  // ── オフラインフォールバック応答生成 ──
  // APIクォータ超過時やネットワーク問題時に使用
  AIResponse _generateOfflineResponse(
      String userMsg, SituationMode situation, int affectionLevel) {
    final lower = userMsg.toLowerCase();

    // キーワードベースの感情・返答生成
    String emotion;
    String text;
    int delta;

    if (_containsAny(lower, ['好き', '愛してる', '可愛い', 'すき', 'love', 'cute'])) {
      emotion = 'love';
      text = affectionLevel > 70
          ? 'えっ…そんなこと言われたら、恥ずかしいじゃないっ…♡　でも、嬉しい…。'
          : '急にそんなこと言わないでよ…！びっくりしたじゃん。';
      delta = 8;
    } else if (_containsAny(lower, ['ありがとう', 'ありがと', 'thank'])) {
      emotion = 'happy';
      text = 'えへへ、どういたしまして♪　そう言ってもらえると嬉しいな！';
      delta = 5;
    } else if (_containsAny(lower, ['元気', 'genki', 'how are you'])) {
      emotion = 'happy';
      text = 'うん、元気だよ！${situation.emoji}　今日も一緒にいてくれてありがとう♪';
      delta = 3;
    } else if (_containsAny(lower, ['悲しい', 'つらい', 'sad', 'lonely'])) {
      emotion = 'sad';
      text = 'えっ、どうしたの…？私がそばにいるから、話してみて？';
      delta = 2;
    } else if (_containsAny(lower, ['怒', 'ムカ', 'angry', 'mad'])) {
      emotion = 'surprised';
      text = 'えっ！？何かあったの…？落ち着いて、深呼吸して？';
      delta = -1;
    } else if (_containsAny(lower, ['ご飯', '食べ', '美味し', 'food', 'eat'])) {
      emotion = 'happy';
      text = 'お腹すいてるの？${situation.emoji}　一緒に何か食べようか？';
      delta = 3;
    } else if (_containsAny(lower, ['天気', '空', '綺麗', 'weather', 'beautiful'])) {
      emotion = 'neutral';
      text = affectionLevel > 60
          ? 'そうだね、${situation.emoji}　こんな日は一緒にいると特別な気分になるね…♪'
          : 'ほんとだね。${situation.emoji}　いい天気だと気持ちいいよね。';
      delta = 2;
    } else if (userMsg.length < 5) {
      // 短い入力
      emotion = 'neutral';
      text = 'どうしたの？もうちょっと話してほしいな♪';
      delta = 0;
    } else {
      // デフォルト応答
      final responses = _getDefaultResponses(situation, affectionLevel);
      final resp = responses[userMsg.length % responses.length];
      emotion = resp['emotion'] as String;
      text = resp['text'] as String;
      delta = resp['delta'] as int;
    }

    final expression = _emotionToExpression[emotion] ?? 'neutral';
    final motion = _emotionToMotion[emotion] ?? 'idle';
    return AIResponse(
      text: text,
      emotion: _toEmotionType(expression),
      expression: expression,
      motion: motion,
      affectionDelta: delta,
    );
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  List<Map<String, dynamic>> _getDefaultResponses(SituationMode situation, int affection) {
    if (situation.id == 'date_park') {
      return [
        {'emotion': 'happy', 'text': '桜がきれいだね…${situation.emoji}　こうして一緒に歩けて嬉しいな♪', 'delta': 3},
        {'emotion': 'shy', 'text': 'ねえ…もうちょっとそばにいてもいいかな？', 'delta': 5},
        {'emotion': 'neutral', 'text': 'ここから見る景色、好きなんだよね。一緒に見れて良かった。', 'delta': 2},
      ];
    } else if (situation.id == 'date_cafe') {
      return [
        {'emotion': 'happy', 'text': 'このカフェのラテアート可愛いね！写真撮ってもいい？', 'delta': 3},
        {'emotion': 'neutral', 'text': 'ゆっくりできる時間って大切だよね。こういう時間が好き♪', 'delta': 2},
        {'emotion': 'shy', 'text': 'ねえ…また来ようね？約束だよ？', 'delta': 4},
      ];
    } else if (situation.id == 'festival') {
      return [
        {'emotion': 'happy', 'text': '屋台がいっぱい！あ、りんご飴食べたい！', 'delta': 3},
        {'emotion': 'surprised', 'text': 'わあ！花火すごい！きれい…！', 'delta': 4},
        {'emotion': 'shy', 'text': '人混みだから…手、繋いでいいかな…？', 'delta': 6},
      ];
    }
    return [
      {'emotion': 'neutral', 'text': 'そうなんだね。もっと話してほしいな♪', 'delta': 1},
      {'emotion': 'happy', 'text': 'えへへ、楽しいね！ずっとこうしていたいな♪', 'delta': 3},
      {'emotion': affection > 60 ? 'shy' : 'neutral',
       'text': affection > 60 ? 'ねえ…今日も一緒にいてくれてありがとう…。' : '今日はどんな話しようか♪',
       'delta': affection > 60 ? 4 : 1},
    ];
  }
}

class AIResponse {
  final String text;
  final EmotionType emotion;
  final String expression;
  final String motion;
  final int affectionDelta;

  const AIResponse({
    required this.text, required this.emotion,
    required this.expression, required this.motion,
    required this.affectionDelta,
  });
}
