/// One message in the conversation between a user and Domix support.
///
/// There is no sender id and no thread id here, and that mirrors the schema exactly: a thread *is*
/// one user, and the only thing the app needs to know about a message is which side wrote it. That
/// single bool decides the bubble's side, its colour and whether it is signed «Поддержка».
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromSupport,
    required this.body,
    required this.sentAt,
  });

  final int id;

  /// true when Domix wrote it, false when the user did. The server sets this itself on both sides
  /// (see `Support.Send` and `Admin.SupportReply`) - it is never taken from a request body, so a
  /// message that claims to be from support really is.
  final bool fromSupport;

  final String body;

  /// Local time. The wire carries RFC3339 in UTC, so this is converted once here rather than at
  /// every place a timestamp is drawn.
  final DateTime sentAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final raw = json['created_at'] as String?;
    // a message always has a timestamp - the column is NOT NULL - so this fallback exists only so a
    // malformed response degrades into a message with a wrong clock rather than a crashed screen
    final parsed = raw == null ? null : DateTime.tryParse(raw);

    return SupportMessage(
      id: json['id'] as int,
      fromSupport: json['from_support'] as bool? ?? false,
      body: json['body'] as String? ?? '',
      sentAt: (parsed ?? DateTime.now().toUtc()).toLocal(),
    );
  }
}

/// A failed support request, carrying the backend's stable machine-readable `code` rather than its
/// message - the same contract [ProductMutationException] and [ShopMutationException] use, and for
/// the same reason: the server writes english and this app renders only ru/uz.
///
/// The codes that matter here are `empty_message`, `message_too_long`, `too_many_messages` and
/// `timeout`; anything else is localized as a generic failure.
class SupportException implements Exception {
  const SupportException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'SupportException($code): $message';
}
