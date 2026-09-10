import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/features/messages/data/support_message.dart';
import 'package:frontend/features/messages/presentation/controllers/support_controller.dart';
import 'package:frontend/features/messages/presentation/widgets/message_bubble.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/core/widgets/circle_back_button.dart';

/// The conversation with Domix support, one row deep in the Сообщения tab.
///
/// [showScaffold] distinguishes the two ways it is drawn: false inside a shell that owns the
/// Scaffold, true as its own route - which is also when it draws a back button. A guest sees why
/// they cannot write rather than a disabled field.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    this.showScaffold = true,
    this.bottomPadding = 36,
    this.isActive = true,
    this.onSignInTap,
  });

  final bool showScaffold;

  /// Room left under the composer for the shell's floating nav bar.
  final double bottomPadding;

  /// Whether this is the tab being looked at. **The shell's `IndexedStack` builds every tab and paints
  /// one**, so `build()` says nothing about visibility and `initState` runs once for the life of the
  /// app - without this signal a reply sent while the app was open would never appear.
  final bool isActive;

  /// Null in a standalone route, which hides the button rather than offering one that goes nowhere.
  final VoidCallback? onSignInTap;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// mirrored into state so the send button can grey out. a listener rather than `onChanged`, so it
  /// stays right when the field is cleared in code.
  bool _canSend = false;

  /// Whether the keyboard is up because of *this* screen's composer. Mirrored into state rather than
  /// read off the node at build time, because it drives [PopScope]'s `canPop` - which has to be
  /// re-evaluated on a focus change, and that is not a rebuild the framework would otherwise do.
  bool _composerFocused = false;

  /// Half of the answer to "is anybody looking at this conversation", the other half being
  /// [MessagesScreen.isActive].
  bool _appResumed = true;

  /// Held rather than looked up in [dispose], where `context.read` asserts. Captured in
  /// [didChangeDependencies], the one callback guaranteed to run before dispose and after the
  /// providers are reachable - the poll has to stop exactly when this screen goes away.
  SupportController? _support;

  @override
  void initState() {
    super.initState();
    _input.addListener(_syncCanSend);
    _inputFocus.addListener(_syncFocus);
    // for AppLifecycleState - the poll must stop when the phone goes in a pocket
    WidgetsBinding.instance.addObserver(this);

    // **not called straight from initState**: `load()` notifies *before* its first await, and initState
    // runs inside the build phase - that is the "setState() called during build" crash
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _support = context.read<SupportController>();
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // the moment this became the visible tab. same post-frame deferral, same reason.
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
    }

    // **and the moment it stopped being it.** the shell's IndexedStack keeps this State alive and its
    // focus with it, so a composer left focused kept the keyboard up over the map, the feed and the
    // profile - which is most of what "the keyboard cannot be dismissed" was.
    if (!widget.isActive && oldWidget.isActive) _inputFocus.unfocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _appResumed = state == AppLifecycleState.resumed;
    // going to the background stops the poll immediately; coming back re-arms it *and* re-fetches
    // through refreshIfStale, so a reply that landed while the phone was asleep is there on the first
    // frame rather than up to ten seconds later
    if (_appResumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfSignedIn());
    } else {
      _support?.setWatching(false);
    }
  }

  @override
  void dispose() {
    // first: a timer that outlives its screen is a request nobody asked for - and, in a widget test, a
    // pending timer the framework fails on
    _support?.setWatching(false);
    // and again on the way out, so a reply that landed while somebody was reading does not light the
    // badge on the list they are about to be looking at
    _support?.markThreadRead();
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_syncCanSend);
    _inputFocus.removeListener(_syncFocus);
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _syncCanSend() {
    final canSend = _input.text.trim().isNotEmpty;
    if (canSend != _canSend) setState(() => _canSend = canSend);

    // a failure message that outlives the thing it was about is noise; typing is the user acting on it
    context.read<SupportController>().clearSendError();
  }

  void _syncFocus() {
    if (_inputFocus.hasFocus == _composerFocused) return;
    setState(() => _composerFocused = _inputFocus.hasFocus);
  }

  /// Puts the keyboard away. Wired to three gestures, because on this screen there was no fourth:
  /// tapping the conversation, dragging it, and the system back button.
  void _dismissKeyboard() {
    if (!_inputFocus.hasFocus) return;
    _inputFocus.unfocus();
  }

  void _loadIfSignedIn() {
    if (!mounted) return;
    // listen: false - this runs from a callback, and the default listen: true *asserts* outside a
    // build. that is a crash, not a performance note.
    if (Provider.of<AuthController>(context, listen: false).profileState.isGuest) return;

    final support = Provider.of<SupportController>(context, listen: false);
    support.refreshIfStale();
    // **having the thread on screen is what "read" means**, so the watermark moves here rather than on
    // a button nobody would press. it only moves forward and only notifies when it moved.
    support.markThreadRead();
  }

  /// Reconciles the live poll with what is on screen. Three independent inputs decide it - the tab is
  /// visible, the app is in the foreground, there is an account - and each changes at a different
  /// moment, so reconciling all three in one place keeps them from needing call sites that disagree.
  void _syncWatching(bool isGuest) {
    if (!mounted) return;
    _support?.setWatching(widget.isActive && _appResumed && !isGuest);
  }

  Future<void> _send() async {
    final controller = context.read<SupportController>();
    final text = _input.text;
    if (text.trim().isEmpty || controller.isSending) return;

    if (await controller.send(text)) {
      // cleared only on success, so a failed send leaves the words in the box rather than making
      // somebody retype their question
      _input.clear();
      _inputFocus.requestFocus();
    }
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
        children: [
          _ChatHeader(
            title: strings.supportChatTitle,
            subtitle: strings.supportChatSubtitle,
            // only as a route: inside the shell there is nothing to pop, and a back arrow that does nothing is
            // worse than none
            onBack: widget.showScaffold ? () => Navigator.of(context).maybePop() : null,
          ),
          Expanded(
            child: isGuest ? _guestState(strings) : _thread(strings),
          ),
          if (!isGuest) _composer(strings),
        ],
      ),
    );

    // **the back gesture closes the keyboard, and it has to be said explicitly here.** Inside the shell
    // this screen is one child of an IndexedStack on the *root* route, so a back press found no route
    // and did nothing at all - and on this screen the IME did not swallow BACK first.
    //
    // `canPop` is false only while this screen's own composer holds focus, so back still exits the app
    // from the home tab.
    final guarded = PopScope(
      canPop: !_composerFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _dismissKeyboard();
      },
      child: body,
    );

    if (!widget.showScaffold) {
      return ColoredBox(color: AppColors.background, child: guarded);
    }
    return Scaffold(backgroundColor: AppColors.background, body: guarded);
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

  /// The conversation, wrapped in the two gestures that put the keyboard away: a tap anywhere on it
  /// (`HitTestBehavior.opaque` is what makes that work over the gaps between bubbles), and a drag,
  /// which has to live on the `ListView` because a scrollable claims it before any ancestor sees it.
  Widget _thread(AppLocalizations strings) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboard,
      child: _threadContent(strings),
    );
  }

  Widget _threadContent(AppLocalizations strings) {
    final controller = context.watch<SupportController>();

    if (controller.isLoading && !controller.hasLoaded) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primaryOrange),
        ),
      );
    }

    if (controller.loadErrorCode != null && !controller.hasLoaded) {
      return EmptyStateView(
        icon: LucideIcons.cloud_off,
        iconColor: AppColors.danger,
        iconBackground: AppColors.dangerSoft,
        title: strings.supportLoadError,
        subtitle: strings.loadErrorHint,
        action: PrimaryActionButton(
          label: strings.retryButtonShort,
          icon: LucideIcons.refresh_cw,
          onTap: () => controller.load(force: true),
        ),
      );
    }

    if (controller.messages.isEmpty) {
      return EmptyStateView(
        icon: LucideIcons.message_square,
        title: strings.supportEmptyTitle,
        subtitle: strings.supportEmptyBody,
      );
    }

    // reverse: true is what makes the list open at its newest message and stay there as the keyboard
    // opens - the alternative is a ScrollController jumping to an offset only known after layout. the
    // item list is reversed to match, so index 0 is the bottom.
    final items = _buildThread(controller.messages, strings).reversed.toList();

    return ListView.builder(
      reverse: true,
      // the other half of the pair above, and it has to live on the scrollable: a `ListView` claims the
      // vertical drag before any ancestor gesture detector is offered it
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  /// Bubbles with a day separator wherever the date changes, oldest first.
  List<Widget> _buildThread(List<SupportMessage> messages, AppLocalizations strings) {
    final widgets = <Widget>[];
    DateTime? previousDay;

    for (final message in messages) {
      final day = DateTime(message.sentAt.year, message.sentAt.month, message.sentAt.day);
      if (previousDay == null || day != previousDay) {
        widgets.add(MessageDaySeparator(label: _dayLabel(day, strings)));
        previousDay = day;
      }
      widgets.add(MessageBubble(message: message, senderLabel: strings.supportSenderLabel));
    }
    return widgets;
  }

  String _dayLabel(DateTime day, AppLocalizations strings) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) return strings.todayLabel;
    if (difference == 1) return strings.yesterdayLabel;
    return '${day.day.toString().padLeft(2, '0')}.'
        '${day.month.toString().padLeft(2, '0')}.${day.year}';
  }

  Widget _composer(AppLocalizations strings) {
    final controller = context.watch<SupportController>();
    final errorCode = controller.sendErrorCode;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, widget.bottomPadding + 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // inline rather than a SnackBar: the shell's nav bar floats over exactly where a SnackBar lands,
          // and a failure the user has to read from under a nav bar is one they will not read
          if (errorCode != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.triangle_alert, size: 15, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.supportSendErrorMessage(errorCode),
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    // grows to five lines and then scrolls: a composer that keeps growing eats the conversation
                    maxLines: 5,
                    // the same 2000 the server enforces, counted in UTF-16 units - a *little* stricter than the
                    // server's rune count on the rarest characters and never looser, so the field can never produce a
                    // message the server will refuse for length
                    maxLength: 2000,
                    // hides the "0/2000" counter the maxLength above would otherwise draw under every keystroke
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: AppColors.textDark, fontSize: 14.5, height: 1.4),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: strings.supportComposerHint,
                      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14.5),
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SendButton(
                enabled: _canSend && !controller.isSending,
                busy: controller.isSending,
                label: strings.supportSendLabel,
                onTap: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tab's own title block. Not an `AppBar`: inside the shell this screen has no Scaffold of its
/// own to hang one on, and a header drawn here is the same header in both modes.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.title, required this.subtitle, this.onBack});

  final String title;
  final String subtitle;

  /// Null inside the shell, where this screen sits on the root route and there is nothing to pop.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 0 on the left when there is a back button, because CircleBackButton carries the gutter inset
      // itself and lands the disc on the same 16px line the title starts on
      padding: EdgeInsets.fromLTRB(onBack == null ? 20 : 0, 14, 20, 14),
      child: Row(
        children: [
          if (onBack case final pop?) ...[
            CircleBackButton(onTap: pop),
            const SizedBox(width: 10),
          ],
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(LucideIcons.life_buoy, size: 20, color: AppColors.primaryOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.easing,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primaryOrange : AppColors.trackGrey,
          borderRadius: BorderRadius.circular(AppRadius.md),
          // the glow only under a button that can actually be pressed - on a disabled one it reads as a
          // control that is merely slow
          boxShadow: enabled ? AppShadows.accent(AppColors.primaryOrange) : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: enabled ? onTap : null,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Icon(
                      LucideIcons.arrow_up,
                      size: 20,
                      color: enabled ? Colors.white : AppColors.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
