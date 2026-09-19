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
import 'package:frontend/core/widgets/screen_header.dart';
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
        ScreenHeader(
          title: strings.ticketsTab,
          subtitle: switch (role) {
            JobRole.client => strings.ticketsClientSubtitle,
            JobRole.worker => strings.ticketsWorkerSubtitle,
            JobRole.shopOwner => strings.ticketsOwnerSubtitle,
          },
          // capped: «Владелец магазина» takes every pixel it is offered, and the title beside it is
          // what pays for that - at 360px it was squeezed to 37px and wrapped mid-word
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: _RolePill(
              label: role.label(strings),
              icon: role.icon,
              onTap: () {
                setState(() => _tab = 0);
                tickets.clearRole();
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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

/// The role pill: what you are on Domix, and the way to stop being it.
///
/// Its own widget rather than inline in the header, because the ellipsis and the `Flexible` around
/// the label are load-bearing - «Владелец магазина» is long enough to overflow the trailing slot on
/// a 360px phone, and an overflow here is a striped bar across the top of the tab.
class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xs + 2);

    return Material(
      color: AppColors.primarySoft,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primaryOrange),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
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
              const Icon(LucideIcons.chevron_down, size: 14, color: AppColors.primaryOrange),
            ],
          ),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // the header asks the question, so the screen does not ask it twice. it used to open with a
        // 64px icon tile over «Кто вы на Domix?» and a paragraph under that - three quarters of the
        // first screen spent introducing three tiles that explain themselves.
        ScreenHeader(title: strings.ticketsTab, subtitle: strings.rolePromptSubtitle),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPadding + 24),
            children: [
              for (final role in JobRole.values) ...[
                RoleOptionTile(
                  icon: role.icon,
                  title: role.label(strings),
                  subtitle: role.subtitle(strings),
                  // null, not false: this list acts on the tap, so it draws a chevron rather than
                  // an empty radio promising a Continue button that is not there
                  isSelected: null,
                  onTap: () => context.read<TicketsController>().setRole(role),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
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
