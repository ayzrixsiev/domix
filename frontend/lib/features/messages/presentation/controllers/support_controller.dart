import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/support_message.dart';
import '../../data/support_repository.dart';

/// Viewmodel behind the Сообщения tab: one conversation, held in memory for the session.
///
/// It is a single list rather than a cache keyed by anything, because there is exactly one thread
/// per installed app - the user's own. When chats with shops arrive this becomes a map keyed by
/// thread the way [ProductsController] is keyed by shop, and nothing else here has to change.
class SupportController extends ChangeNotifier {
  SupportController({SupportRepository? repository})
      : _repo = repository ?? SupportRepository() {
    // unawaited on purpose: the first frame must not wait on a keystore read, and until it lands
    // the watermark is 0, which reads as "everything is unread" - the safe way round for a badge.
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

  /// How long a loaded conversation is trusted before opening the tab re-fetches it.
  ///
  /// Short enough that switching tabs after a minute picks up an answer; long enough that flicking
  /// between tabs is not a request each time. This is the *arrival* path; [_pollOnce] below is what
  /// keeps the thread current once somebody is sitting on it.
  static const _staleAfter = Duration(seconds: 45);

  // ── the live thread ──────────────────────────────────────────────────────────
  //
  // **How a support reply reaches a phone, and why it is a poll.**
  //
  // The app has no push notifications of any kind, so before this the only path was the visibility
  // trigger above: a reply appeared when the user left the Сообщения tab and came back more than 45
  // seconds later. Sit on the tab and it never arrived - which read, correctly, as "answers only show
  // up if I restart the app".
  //
  // Four ways to fix that were on the table:
  //
  //   * **Push notifications** are the real answer and are out of scope here - they mean Firebase, an
  //     Apple key, a token column, and a delivery path to test. Worth building; not this change.
  //   * **Websockets** or **SSE** hold a connection open per phone. On a server that is one small
  //     machine with a ten-connection database pool that is affordable in Go (a goroutine is cheap),
  //     but it is a second protocol to keep alive across a mobile radio that drops it every time the
  //     phone changes cell - so the client ends up owning a reconnect loop *and* a poll for the gap,
  //     which is more moving parts than the poll alone.
  //   * **Long polling** costs no idle traffic and is genuinely tempting. It needs a new endpoint
  //     that holds a request for ~30s, a carve-out in the per-IP rate limiter, and careful handling
  //     of the case where the phone sleeps mid-request - all to save a handful of requests a day.
  //   * **An adaptive poll**, which is this. No new endpoint, no new protocol, and it reuses
  //     `GET /api/support/messages` exactly as it is.
  //
  // What keeps it from being the "tight poll on every open chat" that is not acceptable:
  //
  //   1. **It only runs while somebody is looking.** The tab has to be the visible one *and* the app
  //      has to be in the foreground - see MessagesScreen. Backgrounded or on another tab it costs
  //      literally nothing, which is the state the app is in almost all of the time.
  //   2. **It backs off.** Every poll that finds nothing new doubles the wait, from 10s up to 60s, so
  //      a thread nobody is writing in settles down to one request a minute. Anything that *does*
  //      happen - a reply arriving, the user sending - resets it to attentive.
  //   3. **One request in flight at a time**, because the next one is only armed when the last has
  //      finished. A slow server stretches the interval instead of stacking requests on it.
  //
  // Worst case is a user staring at an open conversation: six requests in the first minute, then one
  // a minute. A single indexed read each, on a table with one row per message per person.

  /// How long to wait after something happened. Also the wait a freshly-opened tab starts from.
  static const _pollFast = Duration(seconds: 10);

  /// The ceiling the back-off climbs to. A reply to a conversation nobody has touched for a couple of
  /// minutes lands within a minute, which is the right trade for a support thread - it is not a chat.
  static const _pollSlow = Duration(seconds: 60);

  Timer? _pollTimer;
  Duration _pollEvery = _pollFast;

  /// When this app last changed the list itself - today, a message being appended by [send].
  ///
  /// A poll that *started* before that moment is answering a question about an older thread, so its
  /// response is dropped rather than applied. That guard is what makes it safe for [_pollOnce] to
  /// accept a list that got **shorter**: before it, the only comparison that could not lose data was
  /// "did it get longer", since a stale response can never be longer than what is already held.
  ///
  /// The shrinking case is real now. Support can clear a conversation from the admin panel, and it
  /// is one table - the messages are gone for both sides. Without this the phone kept showing a
  /// thread that no longer existed for as long as somebody sat on the screen, and only dropped it on
  /// the next full [load] - a tab switch, or a restart.
  DateTime? _lastLocalChange;

  /// Whether a screen is currently showing this thread to somebody. Set by MessagesScreen from three
  /// inputs it owns: the tab is visible, the app is in the foreground, and there is an account.
  bool _watching = false;

  List<SupportMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  /// Machine-readable, never a sentence: this controller must not hold russian text, or the message
  /// would be frozen in whichever language was selected when the request failed.
  String? get loadErrorCode => _loadErrorCode;

  bool get isSending => _isSending;
  String? get sendErrorCode => _sendErrorCode;

  // ── what the chats list needs, and nothing more ───────────────────────────────
  //
  // the row on ChatsScreen is drawn from the thread this controller already holds, which is why
  // there is no `GET /api/chats` and must not be one yet: a list of one conversation the app has
  // in memory would be a round trip to learn what it already knows. when shop chats arrive the app
  // genuinely cannot know a shop wrote to it without asking, and that is when the endpoint earns
  // its place.

  /// The newest message id the reader has had the thread open at. 0 until [_restoreWatermark]
  /// lands, and after a logout.
  int _lastReadId = 0;

  /// The last message in the thread, or null when there is none - what the chats row previews.
  SupportMessage? get lastMessage => _messages.isEmpty ? null : _messages.last;

  /// How many messages *from support* have arrived since the thread was last opened.
  ///
  /// The user's own messages are excluded: they are not news to the person who typed them, and a
  /// badge that lights up when you write something is a badge people stop believing.
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

  /// Moves the watermark to the newest message. Called when the conversation is opened and again
  /// when it is closed, so anything that arrived while somebody was reading is read too.
  ///
  /// **Only moves forward, and notifies only when it moved** - an idempotent call on every poll
  /// would otherwise rebuild the list for nothing.
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
      // the real exception used to be the thing that got lost here in the products feature, and the
      // symptom was a screen blaming the user's connection for a decode bug. log it.
      debugPrint('SupportController: unexpected error loading the thread: $e');
      _loadErrorCode = 'server_error';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches only if the conversation has aged out - what the tab calls when it becomes visible.
  /// A failed load counts as stale, so returning to the tab retries by itself rather than leaving a
  /// dead error message the way the map's did.
  Future<void> refreshIfStale() {
    if (_isLoading) return Future.value();
    if (!_hasLoaded || _loadErrorCode != null || _isStale) return load(force: true);
    return Future.value();
  }

  bool get _isStale {
    final at = _fetchedAt;
    return at == null || DateTime.now().difference(at) > _staleAfter;
  }

  /// Starts or stops the live poll. Idempotent - calling it with the state it is already in does
  /// nothing, which is what lets the screen reconcile it from `build` without thinking about it.
  void setWatching(bool watching) {
    if (watching == _watching) return;
    _watching = watching;

    if (!watching) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    // arriving at the thread is activity, so the back-off starts over. otherwise a tab left open
    // yesterday would resume at one request a minute the moment it was opened again.
    _pollEvery = _pollFast;
    _armPoll();
  }

  /// A one-shot timer re-armed after each poll finishes, rather than `Timer.periodic`.
  ///
  /// The difference matters on a bad connection: a periodic timer keeps firing while a slow request
  /// is still out, so a ten-second server response would leave several identical requests in flight
  /// at once - which is the shape of "hammering the backend" this design exists to avoid.
  void _armPoll() {
    _pollTimer?.cancel();
    if (!_watching) return;
    _pollTimer = Timer(_pollEvery, () async {
      await _pollOnce();
      _armPoll();
    });
  }

  /// One quiet fetch. **Notifies only when the thread actually changed.**
  ///
  /// A poll that notified every time would rebuild the conversation every ten seconds for no reason -
  /// losing a text selection, and re-running the day-separator pass - to redraw exactly what was
  /// already there.
  Future<void> _pollOnce() async {
    // never alongside another request. a poll landing *between* a send's POST and the bubble being
    // appended would replace the list with a copy that does not have it yet, and the message the user
    // just watched arrive would disappear - the exact failure `send` refuses to be optimistic about.
    if (_isLoading || _isSending || !_watching) return;

    final startedAt = DateTime.now();

    try {
      final fresh = await _repo.fetchMessages();
      // still the tab on screen? the await above can outlive a tab switch or a logout.
      if (!_watching) return;

      // a send landed while this request was in flight, so this answer predates the message the user
      // is already looking at. dropping it is what lets the comparison below accept a shorter list.
      final localChange = _lastLocalChange;
      if (localChange != null && localChange.isAfter(startedAt)) return;

      _fetchedAt = DateTime.now();

      // **the thread is the same thread when it is the same length and ends on the same message.**
      // Length alone was enough while the table was insert-only in both directions; support can now
      // clear a conversation, so "shorter" is a real answer and not evidence of a stale response -
      // which the guard above is what rules out.
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
      // **a failed poll is not something the screen shows.** the conversation on screen is still the
      // last known good one, and turning a blip of no signal into an error state would replace a
      // readable thread with a retry button. it just backs off and tries again.
      debugPrint('SupportController: a background poll failed ($e) - backing off');
      _backOff();
    }
  }

  /// Doubles the wait, up to the ceiling. Called on both the "nothing new" and the "that failed"
  /// paths, because from the server's point of view they cost the same and neither is a reason to
  /// keep asking at the same rate.
  void _backOff() {
    final doubled = _pollEvery * 2;
    _pollEvery = doubled > _pollSlow ? _pollSlow : doubled;
  }

  /// Sends [text]. Returns true when it landed; [sendErrorCode] holds the reason when it did not.
  ///
  /// The sent message is appended from the server's response rather than optimistically: this is a
  /// support request, and a bubble that appears and then silently is not there is worse than a
  /// second of waiting. The composer keeps the text on failure so nothing has to be retyped.
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
      // asking a question is the moment an answer is most likely, so the poll goes back to its
      // shortest interval however long it had been idling before
      _pollEvery = _pollFast;
      _armPoll();
    } on SupportException catch (e) {
      _sendErrorCode = e.code;
    } on TimeoutException {
      // its own code, because "the request did not come back in ten seconds" and "the server said
      // no" need different words - the first is nearly always transient and the advice is to press
      // send again, which is the opposite of what a generic failure suggests.
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

  /// Drops the conversation when the session ends.
  ///
  /// **This is not tidying up, it is the privacy of the thread.** A support conversation is where
  /// somebody typed their phone number and their problem; leaving it in memory after a logout means
  /// the next person to sign in on this phone opens Сообщения and reads it. Wired from `main()`
  /// alongside the shop list's own handler.
  ///
  /// Silent - no `notifyListeners`. It is called from inside [AuthController.logout], which already
  /// notifies, and the tab is not on screen at that moment.
  void handleSessionEnded() {
    // first, and not last: the poll fetches *the caller's* thread, so one still armed after a logout
    // would be a request for whoever signs in next - or a 401 loop for nobody at all.
    setWatching(false);

    _messages = const [];
    _hasLoaded = false;
    _isLoading = false;
    _loadErrorCode = null;
    _sendErrorCode = null;
    _fetchedAt = null;

    // the watermark is a fact about one person's reading, so it goes with their thread - otherwise
    // the next account on this phone opens a conversation that is already marked read.
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
