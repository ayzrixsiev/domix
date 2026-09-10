import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/support_message.dart';
import '../../data/support_repository.dart';

/// Viewmodel behind the Сообщения tab: one conversation, held in memory for the session. A single
/// list rather than a cache, since there is exactly one thread per install - shop chats would make
/// it a map keyed by thread, the way [ProductsController] is keyed by shop.
class SupportController extends ChangeNotifier {
  SupportController({SupportRepository? repository})
      : _repo = repository ?? SupportRepository() {
    // unawaited: the first frame must not wait on a keystore read, and until it lands the watermark is
    // 0, which reads as "everything is unread" - the safe way round for a badge
    _restoreWatermark();
  }

  final SupportRepository _repo;

  List<SupportMessage> _messages = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _loadErrorCode;

  bool _isSending = false;
  String? _sendErrorCode;

  DateTime? _fetchedAt;

  /// How long a loaded conversation is trusted before opening the tab re-fetches it. This is the
  /// *arrival* path; [_pollOnce] is what keeps the thread current once somebody is sitting on it.
  static const _staleAfter = Duration(seconds: 45);

  // ── the live thread ──
  //
  // The app has no push notifications, so a reply reaches an already-open tab by polling. Three
  // properties keep that from being a tight poll on every open chat: **it only runs while somebody is
  // looking** (the tab visible *and* the app in the foreground); **it backs off**, doubling from 10s
  // to 60s until something happens; and **one request is in flight at a time**.

  /// How long to wait after something happened. Also the wait a freshly-opened tab starts from.
  static const _pollFast = Duration(seconds: 10);

  /// The ceiling the back-off climbs to. A support thread is answered over hours, not a chat.
  static const _pollSlow = Duration(seconds: 60);

  Timer? _pollTimer;
  Duration _pollEvery = _pollFast;

  /// When this app last changed the list itself - today, a message appended by [send]. A poll that
  /// *started* before that moment answers a question about an older thread, so its response is
  /// dropped: that guard is what lets [_pollOnce] accept a list that got **shorter**, which is real,
  /// since support can clear a conversation from the admin panel.
  DateTime? _lastLocalChange;

  /// Set by MessagesScreen from three inputs it owns: the tab is visible, the app is in the
  /// foreground, and there is an account.
  bool _watching = false;

  List<SupportMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  /// Machine-readable, never a sentence: russian text here would be frozen in whichever language was
  /// selected when the request failed.
  String? get loadErrorCode => _loadErrorCode;

  bool get isSending => _isSending;
  String? get sendErrorCode => _sendErrorCode;

  // the row on ChatsScreen is drawn from the thread this controller already holds, which is why there
  // is no `GET /api/chats` yet - it would be a round trip to learn what the app knows

  /// The newest message id the reader has had the thread open at. 0 until [_restoreWatermark] lands.
  int _lastReadId = 0;

  /// The last message in the thread, or null when there is none - what the chats row previews.
  SupportMessage? get lastMessage => _messages.isEmpty ? null : _messages.last;

  /// From support only: the user's own messages are not news to whoever typed them, and a badge that
  /// lights up when you write something is a badge people stop believing.
  int get unreadCount {
    var count = 0;
    for (final message in _messages) {
      if (message.fromSupport && message.id > _lastReadId) count++;
    }
    return count;
  }

  Future<void> _restoreWatermark() async {
    final stored = await _repo.readWatermark();
    if (stored == _lastReadId) return;
    _lastReadId = stored;
    notifyListeners();
  }

  /// Moves the watermark to the newest message - called when the thread is opened and again when it
  /// is closed. **Only moves forward, and notifies only when it moved**, or every poll would rebuild.
  Future<void> markThreadRead() async {
    final newest = lastMessage;
    if (newest == null || newest.id <= _lastReadId) return;

    _lastReadId = newest.id;
    notifyListeners();
    await _repo.writeWatermark(_lastReadId);
  }

  /// Loads the conversation. [force] re-fetches one already in hand.
  Future<void> load({bool force = false}) async {
    if (_isLoading) return; // a second call while one is in flight is a no-op
    if (!force && _hasLoaded && !_isStale) return;

    _isLoading = true;
    _loadErrorCode = null;
    notifyListeners();

    try {
      _messages = await _repo.fetchMessages();
      _hasLoaded = true;
      _fetchedAt = DateTime.now();
    } on SupportException catch (e) {
      _loadErrorCode = e.code;
    } on TimeoutException {
      _loadErrorCode = 'timeout';
    } catch (e) {
      // the real exception is what gets lost otherwise, and the symptom is a screen blaming the user's
      // connection for a decode bug
      debugPrint('SupportController: unexpected error loading the thread: $e');
      _loadErrorCode = 'server_error';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches only if the conversation has aged out - what the tab calls when it becomes visible.
  /// A failed load counts as stale, so returning retries by itself rather than leaving a dead error.
  Future<void> refreshIfStale() {
    if (_isLoading) return Future.value();
    if (!_hasLoaded || _loadErrorCode != null || _isStale) return load(force: true);
    return Future.value();
  }

  bool get _isStale {
    final at = _fetchedAt;
    return at == null || DateTime.now().difference(at) > _staleAfter;
  }

  /// Idempotent, which is what lets the screen reconcile it from `build` without thinking about it.
  void setWatching(bool watching) {
    if (watching == _watching) return;
    _watching = watching;

    if (!watching) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    // arriving at the thread is activity, so the back-off starts over - otherwise a tab left open
    // yesterday would resume at one request a minute the moment it was opened again
    _pollEvery = _pollFast;
    _armPoll();
  }

  /// A one-shot timer re-armed after each poll finishes, rather than `Timer.periodic`: a periodic
  /// timer keeps firing while a slow request is still out, leaving several identical ones in flight.
  void _armPoll() {
    _pollTimer?.cancel();
    if (!_watching) return;
    _pollTimer = Timer(_pollEvery, () async {
      await _pollOnce();
      _armPoll();
    });
  }

  /// One quiet fetch. **Notifies only when the thread actually changed** - otherwise it would rebuild
  /// the conversation every ten seconds, losing a text selection, to redraw what was already there.
  Future<void> _pollOnce() async {
    // never alongside another request: a poll landing between a send's POST and its bubble being
    // appended would replace the list with a copy that does not have it yet
    if (_isLoading || _isSending || !_watching) return;

    final startedAt = DateTime.now();

    try {
      final fresh = await _repo.fetchMessages();
      // still the tab on screen? the await above can outlive a tab switch or a logout.
      if (!_watching) return;

      // a send landed while this request was in flight, so this answer predates the message the user is
      // already looking at. dropping it is what lets the comparison below accept a shorter list.
      final localChange = _lastLocalChange;
      if (localChange != null && localChange.isAfter(startedAt)) return;

      _fetchedAt = DateTime.now();

      // **the same thread when it is the same length and ends on the same message.** length alone was
      // enough while the table was insert-only in both directions; support can clear a conversation now,
      // so "shorter" is a real answer and not a stale response - which the guard above rules out.
      if (fresh.length == _messages.length &&
          (fresh.isEmpty || fresh.last.id == _messages.last.id)) {
        _backOff();
        return;
      }

      _messages = fresh;
      _hasLoaded = true;
      _loadErrorCode = null;
      _pollEvery = _pollFast; // something is happening - stay attentive
      notifyListeners();
    } catch (e) {
      // **a failed poll is not something the screen shows**: the conversation on screen is still the last
      // known good one, and a blip of no signal must not replace it with a retry button
      debugPrint('SupportController: a background poll failed ($e) - backing off');
      _backOff();
    }
  }

  /// Doubles the wait, up to the ceiling. Called on both the "nothing new" and the "that failed"
  /// paths - from the server's point of view they cost the same.
  void _backOff() {
    final doubled = _pollEvery * 2;
    _pollEvery = doubled > _pollSlow ? _pollSlow : doubled;
  }

  /// Sends [text]. Returns true when it landed; [sendErrorCode] holds the reason when it did not.
  /// Appended from the server's response rather than optimistically: a bubble that appears and then
  /// silently is not there is worse than a second of waiting.
  Future<bool> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _isSending) return false;

    _isSending = true;
    _sendErrorCode = null;
    notifyListeners();

    var sent = false;
    try {
      final message = await _repo.sendMessage(body);
      _messages = [..._messages, message];
      // stamped so an in-flight poll started before this cannot answer with a list that does not
      // have it yet - see _lastLocalChange
      _lastLocalChange = DateTime.now();
      _hasLoaded = true;
      // the thread now ends with something we put there ourselves, so it is as fresh as a fetch
      _fetchedAt = DateTime.now();
      sent = true;
      // asking a question is the moment an answer is most likely, so the poll returns to its shortest
      // interval however long it had been idling
      _pollEvery = _pollFast;
      _armPoll();
    } on SupportException catch (e) {
      _sendErrorCode = e.code;
    } on TimeoutException {
      // its own code: "did not come back in ten seconds" is nearly always transient and the advice is to
      // press send again, which is the opposite of what a generic failure suggests
      _sendErrorCode = 'timeout';
    } catch (e) {
      debugPrint('SupportController: unexpected error sending a message: $e');
      _sendErrorCode = 'server_error';
    }

    _isSending = false;
    notifyListeners();
    return sent;
  }

  void clearSendError() {
    if (_sendErrorCode == null) return;
    _sendErrorCode = null;
    notifyListeners();
  }

  /// Drops the conversation when the session ends. **Not tidying up - the privacy of the thread**,
  /// which is where somebody typed their phone number and their problem. Silent:
  /// [AuthController.logout] already notifies, and the tab is not on screen at that moment.
  void handleSessionEnded() {
    // first, and not last: the poll fetches *the caller's* thread, so one still armed after a logout
    // would be a request for whoever signs in next - or a 401 loop for nobody at all
    setWatching(false);

    _messages = const [];
    _hasLoaded = false;
    _isLoading = false;
    _loadErrorCode = null;
    _sendErrorCode = null;
    _fetchedAt = null;

    // the watermark is a fact about one person's reading, so it goes with their thread
    _lastReadId = 0;
    _lastLocalChange = null;
    _repo.clearWatermark();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
