/// One message in the conversation between a user and Domix support. No sender id and no thread id,
/// mirroring the schema: a thread *is* one user, and the only thing the app needs to know is which
/// side wrote it.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.fromSupport,
    required this.body,
    required this.sentAt,
  });

  final int id;

  /// the server sets this itself on both sides and never takes it from a request body, so a message
  /// that claims to be from support really is
  final bool fromSupport;

  final String body;

  /// Local time. The wire carries RFC3339 in UTC, converted once here rather than at every draw.
  final DateTime sentAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final raw = json['created_at'] as String?;
    // the column is NOT NULL, so this fallback exists only so a malformed response degrades into a
    // wrong clock rather than a crashed screen
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
/// message - the same contract [ProductMutationException] and [ShopMutationException] use, since the
/// server writes english and this app renders only ru/uz.
class SupportException implements Exception {
  const SupportException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'SupportException($code): $message';
}
