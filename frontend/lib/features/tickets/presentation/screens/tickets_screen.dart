import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/constants/app_theme.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/core/localization/language_provider.dart';
import 'package:frontend/core/widgets/empty_state_view.dart';
import 'package:frontend/core/widgets/primary_action_button.dart';
import 'package:frontend/core/widgets/role_option_tile.dart';
import 'package:frontend/core/widgets/segmented_tabs.dart';
import 'package:frontend/features/profile/presentation/controllers/auth_controller.dart';
import 'package:frontend/features/tickets/data/job_role.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';
import 'package:frontend/features/tickets/presentation/controllers/tickets_controller.dart';
import 'package:frontend/features/tickets/presentation/screens/create_ticket_screen.dart';
import 'package:frontend/features/tickets/presentation/widgets/ticket_card.dart';
import 'package:frontend/features/tickets/presentation/widgets/worker_card.dart';
import 'package:frontend/features/tickets/presentation/widgets/worker_profile_form.dart';

/// The Заявки tab: **three screens behind one nav item**, chosen by [JobRole].
///
/// A job marketplace is two-sided and the two sides want opposite things from the same data, so one
/// screen with everything on it would give both a tab mostly full of somebody else's job. The shop
/// owner is the third side and the reason the split is a role rather than a boolean: they are
/// watching for the client about to buy two hundred square metres of tile.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key, this.showScaffold = true, this.bottomPadding = 36});

  final bool showScaffold;
  final double bottomPadding;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  /// Reset on a role change, because index 1 means «Рабочие» to a client and «Моя анкета» to a worker.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final strings = Provider.of<LanguageProvider>(context).strings;
    final tickets = context.watch<TicketsController>();
    final role = tickets.role;

    // the анкета is titled with the account's own name. done here rather than at login because this
    // controller must not import the auth one - `main()` owns the wiring between features. after the
    // frame, never during it: setProfileName notifies. it is a no-op after the first pass.
    final accountName = context.watch<AuthController>().profileState.fullName;
    if (role == JobRole.worker && accountName.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) tickets.setProfileName(accountName);
      });
    }

    final body = SafeArea(
      bottom: false,
      child: role == null
          ? _RoleChooser(strings: strings, bottomPadding: widget.bottomPadding)
          : _roleView(role, tickets, strings),
    );

    if (!widget.showScaffold) {
      return ColoredBox(color: AppColors.background, child: body);
    }
    return Scaffold(backgroundColor: AppColors.background, body: body);
  }

  Widget _roleView(JobRole role, TicketsController tickets, AppLocalizations strings) {
    final tabs = switch (role) {
      JobRole.client => [strings.tabMyTickets, strings.tabWorkers],
      JobRole.worker => [strings.tabJobFeed, strings.tabMyProfile],
      JobRole.shopOwner => [strings.tabMaterialRequests, strings.tabMyOffers],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: strings.ticketsTab,
          subtitle: switch (role) {
            JobRole.client => strings.ticketsClientSubtitle,
            JobRole.worker => strings.ticketsWorkerSubtitle,
            JobRole.shopOwner => strings.ticketsOwnerSubtitle,
          },
          roleLabel: role.label(strings),
          roleIcon: role.icon,
          onSwitchRole: () {
            setState(() => _tab = 0);
            tickets.clearRole();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SegmentedTabs(
            labels: tabs,
            selected: _tab,
            onSelected: (index) => setState(() => _tab = index),
          ),
        ),
        Expanded(child: _tabView(role, tickets, strings)),
      ],
    );
  }

  Widget _tabView(JobRole role, TicketsController tickets, AppLocalizations strings) {
    return switch ((role, _tab)) {
      (JobRole.client, 0) => _myTickets(tickets, strings),
      (JobRole.client, _) => _workers(tickets, strings),
      (JobRole.worker, 0) => _jobFeed(tickets, strings, tickets.openTickets),
      (JobRole.worker, _) => WorkerProfileForm(
        strings: strings,
        bottomPadding: widget.bottomPadding,
      ),
      (JobRole.shopOwner, 0) => _materialFeed(tickets, strings),
      (JobRole.shopOwner, _) => _myOffers(tickets, strings),
    };
  }

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPadding + 16);

  /// The client's own list. The post button sits **above** the tickets rather than floating over them:
  /// the shell already has a floating bar at the bottom, and a second floating control over the same
  /// 90 pixels is two things fighting for the same thumb.
  Widget _myTickets(TicketsController tickets, AppLocalizations strings) {
    return ListView.separated(
      padding: _listPadding,
      itemCount: tickets.myTickets.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            // a Row rather than an Align: a list item is laid out with an unbounded height, and Align with no
            // height factor answers "as big as possible" - which is infinity
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PrimaryActionButton(
                  label: strings.createTicketAction,
                  icon: LucideIcons.plus,
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const CreateTicketScreen())),
                ),
              ],
            ),
          );
        }

        return TicketCard(ticket: tickets.myTickets[index - 1], strings: strings, showStatus: true);
      },
    );
  }

  Widget _workers(TicketsController tickets, AppLocalizations strings) {
    return ListView.separated(
      padding: _listPadding,
      itemCount: tickets.workers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => WorkerCard(
        worker: tickets.workers[index],
        strings: strings,
        // the client-worker chat is the piece that genuinely is not built - the Сообщения tab holds one
        // thread and it is support. saying so is better than a button that opens the wrong conversation.
        onContact: () => _toast(strings.workerContactSoon),
      ),
    );
  }

  /// The worker's feed and the shop owner's share this builder - the difference is which tickets are
  /// in the list and what the button on them says.
  Widget _jobFeed(
    TicketsController tickets,
    AppLocalizations strings,
    List<JobTicket> feed, {
    String? actionLabel,
    String? doneLabel,
    IconData? actionIcon,
  }) {
    return ListView.separated(
      padding: _listPadding,
      itemCount: feed.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final ticket = feed[index];
        return TicketCard(
          ticket: ticket,
          strings: strings,
          actionLabel: actionLabel ?? strings.respondAction,
          doneLabel: doneLabel ?? strings.respondedLabel,
          actionIcon: actionIcon ?? LucideIcons.send,
          isDone: tickets.hasResponded(ticket.id),
          onAction: () {
            tickets.respondTo(ticket.id);
            _toast(doneLabel ?? strings.respondedLabel);
          },
        );
      },
    );
  }

  Widget _materialFeed(TicketsController tickets, AppLocalizations strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _HintCard(text: strings.ownerFeedHint),
        ),
        Expanded(
          child: _jobFeed(
            tickets,
            strings,
            tickets.materialTickets,
            actionLabel: strings.offerMaterialsAction,
            doneLabel: strings.offerSentLabel,
            actionIcon: LucideIcons.store,
          ),
        ),
      ],
    );
  }

  Widget _myOffers(TicketsController tickets, AppLocalizations strings) {
    final offered = tickets.materialTickets
        .where((ticket) => tickets.hasResponded(ticket.id))
        .toList(growable: false);

    if (offered.isEmpty) {
      return EmptyStateView(
        icon: LucideIcons.store,
        title: strings.noOffersTitle,
        subtitle: strings.noOffersBody,
        bottomInset: widget.bottomPadding,
      );
    }

    return ListView.separated(
      padding: _listPadding,
      itemCount: offered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => TicketCard(
        ticket: offered[index],
        strings: strings,
        actionLabel: strings.offerMaterialsAction,
        doneLabel: strings.offerSentLabel,
        isDone: true,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// The tab's title block, with the current role as a pill that is also the way to change it. **The
/// role is on screen rather than only implied by the layout**: somebody who picked the wrong one at
/// registration has otherwise no way to find out that is what happened.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.roleLabel,
    required this.roleIcon,
    required this.onSwitchRole,
  });

  final String title;
  final String subtitle;
  final String roleLabel;
  final IconData roleIcon;
  final VoidCallback onSwitchRole;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // **the subtitle gets its own line, and the pill is Flexible** - both matter at 360px: a Row hands
          // its non-flex children unbounded width, so beside a wrapping subtitle «Владелец магазина» took
          // everything and squeezed the title column to 37px. the title is short in both languages, so it is
          // the one that stays non-flex.
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 22,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              // Expanded + an inner end-aligned Row, rather than a Spacer beside a Flexible pill: two flex
              // children split the free width 50/50, which cut «Владелец магазина» in half with 120px sitting
              // empty beside it. this gives the pill all the room there is.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Material(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.xs + 2),
                          onTap: onSwitchRole,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(roleIcon, size: 14, color: AppColors.primaryOrange),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    roleLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.primaryOrange,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  LucideIcons.chevron_down,
                                  size: 14,
                                  color: AppColors.primaryOrange,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Asks the question the tab cannot answer for itself - reachable by a guest and by anybody who taps
/// the role pill. **A guest can choose here without an account**: the whole marketplace is behind
/// this one decision, and demanding a login first is how a two-sided market looks empty to everybody.
class _RoleChooser extends StatelessWidget {
  const _RoleChooser({required this.strings, required this.bottomPadding});

  final AppLocalizations strings;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 28, 20, bottomPadding + 24),
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(LucideIcons.hard_hat, size: 28, color: AppColors.primaryOrange),
        ),
        const SizedBox(height: 18),
        Text(
          strings.rolePromptTitle,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 21,
            height: 1.25,
            letterSpacing: -0.3,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          strings.rolePromptBody,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 13.5, height: 1.45),
        ),
        const SizedBox(height: 20),
        for (final role in JobRole.values) ...[
          RoleOptionTile(
            icon: role.icon,
            title: role.label(strings),
            subtitle: role.subtitle(strings),
            // null, not false: this list acts on the tap, so it draws a chevron rather than an empty radio
            // promising a Continue button that is not there
            isSelected: null,
            onTap: () => context.read<TicketsController>().setRole(role),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One line explaining why a shop owner is looking at other people's renovation jobs - without it
/// the first read of that screen is "why am I being shown this".
class _HintCard extends StatelessWidget {
  const _HintCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.sparkles, size: 15, color: AppColors.primaryOrange),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
