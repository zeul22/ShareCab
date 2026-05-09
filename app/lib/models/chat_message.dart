/// One chat message inside a [MatchGroup]'s coordination thread.
///
/// Backend persists these via `POST /api/chats/:groupId` and emits a
/// `chat:message` socket event with the same shape on the `group:{id}` room.
class ChatMessage {
  final String id;
  final String groupId;
  final String senderId;

  /// Sender's display name (first word) — backend populates via the
  /// `path: 'sender', select: 'name rating'` projection.
  final String senderName;

  final String content;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.sentAt,
  });

  bool isFromMe(String? myUserId) => myUserId != null && senderId == myUserId;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    String senderId;
    String senderName = 'Co-rider';
    if (sender is Map<String, dynamic>) {
      senderId = (sender['_id'] as String?) ?? '';
      final raw = (sender['name'] as String? ?? '').trim();
      if (raw.isNotEmpty) senderName = raw.split(' ').first;
    } else {
      senderId = sender is String ? sender : '';
    }
    return ChatMessage(
      id: (json['_id'] as String?) ?? '',
      groupId: (json['matchGroup'] as String?) ?? '',
      senderId: senderId,
      senderName: senderName,
      content: (json['content'] as String?) ?? '',
      sentAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
