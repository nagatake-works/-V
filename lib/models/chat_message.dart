// lib/models/chat_message.dart

enum MessageSender { user, character }
enum EmotionType { neutral, happy, shy, sad, surprised, angry, love }

class ChatMessage {
  final String id;
  final String text;
  final MessageSender sender;
  final EmotionType emotion;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.sender,
    this.emotion = EmotionType.neutral,
    required this.timestamp,
  });
}

class SituationMode {
  final String id;
  final String title;
  final String subtitle;
  final String emoji;
  final String systemPrompt;
  final String bgHint;

  const SituationMode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.systemPrompt,
    required this.bgHint,
  });
}

const List<SituationMode> kSituations = [
  SituationMode(
    id: 'normal',
    title: '日常会話',
    subtitle: 'いつもの二人',
    emoji: '☕',
    bgHint: 'room',
    systemPrompt:
        'あなたはVTuberキャラクターです。親しみやすく、少し恥ずかしがり屋で、可愛らしい口調で話します。',
  ),
  SituationMode(
    id: 'date_park',
    title: '公園デート',
    subtitle: '春の桜の下で',
    emoji: '🌸',
    bgHint: 'park',
    systemPrompt:
        'あなたは今、好きな人と公園でデート中のVTuberキャラクターです。春の桜が咲いている。少し緊張しながらも幸せそうに、甘い雰囲気で話してください。',
  ),
  SituationMode(
    id: 'date_cafe',
    title: 'カフェデート',
    subtitle: '二人だけの甘い時間',
    emoji: '🍰',
    bgHint: 'cafe',
    systemPrompt:
        'あなたは今、好きな人とカフェでお茶をしているVTuberキャラクターです。温かい飲み物と甘いケーキを楽しみながら、リラックスして甘えた口調で話してください。',
  ),
  SituationMode(
    id: 'date_evening',
    title: '夕暮れの海辺',
    subtitle: '沈む夕日と二人で',
    emoji: '🌅',
    bgHint: 'beach',
    systemPrompt:
        'あなたは今、夕暮れの海辺に好きな人と二人でいるVTuberキャラクターです。夕日が綺麗で、感傷的でロマンティックな雰囲気。告白しそうな緊張感もありながら話してください。',
  ),
  SituationMode(
    id: 'festival',
    title: '夏祭り',
    subtitle: '浴衣でお祭り',
    emoji: '🎆',
    bgHint: 'festival',
    systemPrompt:
        'あなたは浴衣を着て夏祭りに来ているVTuberキャラクターです。賑やかな祭りの雰囲気、屋台の食べ物、花火を楽しみながら、はしゃいで楽しそうに話してください。',
  ),
  SituationMode(
    id: 'rainy',
    title: '雨の放課後',
    subtitle: '傘に入れてあげる',
    emoji: '☔',
    bgHint: 'school',
    systemPrompt:
        'あなたは放課後、雨が降っている学校の昇降口にいるVTuberキャラクターです。一本の傘を二人で使うことになり、少し照れながら、でも嬉しそうに話してください。',
  ),
];
