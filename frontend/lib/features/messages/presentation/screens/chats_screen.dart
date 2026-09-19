import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/screen_header.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/messages/presentation/controllers/support_controller.dart';
import 'package:frontend/features/messages/presentation/screens/messages_screen.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';

/// The Сообщения tab: a **list of conversations**, one row per thread, with the conversation itself
/// on a pushed route. Today the list has exactly one row - Domix support - and it is built now
/// because the second kind of conversation would otherwise move the chat out from under a habit.
///
/// **Nothing here fetches a list**: the row is drawn from the thread [SupportController] already
/// holds. It owns the same three-input poll reconciliation [MessagesScreen] does, because the
/// preview and the unread count go stale exactly as fast as the thread does.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.isActive = true,
    this.onSignInTap,
  });

  final bool showScaffold;

  /// Room left under the list for the shell's floating nav bar.
  final double bottomPadding;

  /// Whether this is the tab being looked at. **`build()` running is not a visibility signal under
  /// the shell's `IndexedStack`**, so the shell passes the edge down and the poll hangs off it.
  final bool isActive;

  /// Sends a guest to the profile tab, where logging in actually happens.
  final VoidCallback? onSignInTap;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  /// Whether the app itself is in the foreground - half of "is anybody looking at this list".
  bool _appResumed = true;

  /// Whether the conversation is pushed on top of this screen. While it is, *it* owns the poll - and
  /// this screen must not be tricked by the pop into thinking nobody is watching.
  bool _chatIsOpen = false;

  /// Held rather than looked up in [dispose], where `context.read` asserts: the element's ancestors
  /// are already being deactivated by then.
  SupportController? _support;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // not straight from initState: load() notifies before its first await, and initState runs inside
    // the build phase - that is the "setState() called during build" crash
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _support = context.read<SupportController>();
  }

  @override
  void didUpdateWidget(covariant ChatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
    } else {
      _support?.setWatching(false);
    }
  }

  @override
  void dispose() {
    _support?.setWatching(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _loadIfSignedIn() {
    if (!mounted) return;
    // listen: false - this runs from a callback, and the default listen: true *asserts* outside a build
    if (Provider.of<AuthController>(context, listen: false).profileState.isGuest) return;
    Provider.of<SupportController>(context, listen: false).refreshIfStale();
  }

  /// Reconciles the poll with what is on screen: the tab is visible, the app is in the foreground,
  /// there is an account, and the conversation is not already polling on its own.
  /// [SupportController.setWatching] is idempotent, so running this every frame costs a comparison.
  void _syncWatching(bool isGuest) {
    if (!mounted) return;
    _support?.setWatching(widget.isActive && _appResumed && !isGuest && !_chatIsOpen);
  }

  /// Opens the conversation, and re-arms this screen's poll on the way back - not belt and braces:
  /// [MessagesScreen.dispose] stops the poll, and popping a route does not rebuild the one below it.
  Future<void> _openSupportChat() async {
    _chatIsOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const MessagesScreen()),
    );
    _chatIsOpen = false;
    if (!mounted) return;
    // whatever arrived while it was open has now been read
    await _support?.markThreadRead();
    if (!mounted) return;
    _syncWatching(context.read<AuthController>().profileState.isGuest);
  }

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final isGuest = context.watch<AuthController>().profileState.isGuest;

    // after the frame, never during it: this starts and stops a timer. `context.watch` above is what
    // makes a login or a logout reach it at all - the rebuild is the signal.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWatching(isGuest));

    final body = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: strings.chatsScreenTitle, subtitle: strings.chatsScreenSubtitle),
          Expanded(child: isGuest ? _guestState(strings) : _threads(strings)),
        ],
      ),
    );

    if (!widget.showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }
    return Scaffold(backgroundColor: AppColors.background, body: body);
  }

  Widget _guestState(AppLocalizations strings) {
    return EmptyStateView(
      icon: LucideIcons.message_square,
      title: strings.supportGuestTitle,
      subtitle: strings.supportGuestBody,
      bottomInset: widget.bottomPadding,
      action: widget.onSignInTap == null
          ? null
          : PrimaryActionButton(
              label: strings.supportGuestAction,
              icon: LucideIcons.log_in,
              onTap: widget.onSignInTap!,
            ),
    );
  }

  /// A `ListView` rather than a `Column` for one row, because the second and third rows are the whole
  /// reason this screen exists.
  Widget _threads(AppLocalizations strings) {
    final controller = context.watch<SupportController>();
    final last = controller.lastMessage;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPadding + 16),
      children: [
        ChatListRow(
          icon: LucideIcons.life_buoy,
          title: strings.supportSenderLabel,
          // the thread's own last line, prefixed when it was the reader's - without it a row shows your own
          // question back to you as though it had been answered
          preview: last == null
              ? strings.supportChatSubtitle
              : '${last.fromSupport ? '' : strings.chatPreviewYou}${last.body}',
          timeLabel: last == null ? null : _timeLabel(last.sentAt, strings),
          unreadCount: controller.unreadCount,
          onTap: _openSupportChat,
        ),
      ],
    );
  }

  /// Time for today, «Вчера» for yesterday, a date before that - what fits in the width a row has.
  String _timeLabel(DateTime at, AppLocalizations strings) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (difference == 1) return strings.yesterdayLabel;
    return '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
  }
}

/// One conversation in the list. **Written with no idea what a support thread is**, because the
/// second and third callers are a shop and a worker - what must not differ is the layout, since a
/// chat list where one row is taller than another looks broken before it is read.
class ChatListRow extends StatelessWidget {
  const ChatListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.preview,
    required this.onTap,
    this.timeLabel,
    this.unreadCount = 0,
  });

  final IconData icon;
  final String title;
  final String preview;

  /// Null before there is a message to have a time.
  final String? timeLabel;

  final int unreadCount;
  final VoidCallback onTap;

  bool get _hasUnread => unreadCount > 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 21, color: AppColors.primaryOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        // an unread row is darker and heavier - the second channel beside the badge, since a count alone
                        // is a small orange dot in the corner of a row that otherwise looks read
                        color: _hasUnread ? AppColors.textDark : AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: _hasUnread ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel ?? '',
                    style: TextStyle(
                      color: _hasUnread ? AppColors.primaryOrange : AppColors.textFaint,
                      fontSize: 11,
                      fontWeight: _hasUnread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 7),
                  // the badge disappears entirely at zero rather than drawing a "0": a badge that is always there is
                  // a badge nobody reads
                  if (_hasUnread)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
