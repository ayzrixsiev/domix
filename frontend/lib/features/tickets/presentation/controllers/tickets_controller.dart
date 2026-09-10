import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:frontend/features/tickets/data/demo_job_market.dart';
import 'package:frontend/features/tickets/data/job_category.dart';
import 'package:frontend/features/tickets/data/job_role.dart';
import 'package:frontend/features/tickets/data/job_ticket.dart';

/// Holds the Заявки tab: which side of the market this phone is on, and the market itself.
///
/// **Everything below the role is a fixture in memory** - see [DemoJobMarket]. This class is the
/// seam, so swapping the fixtures for a repository is a change to this file and nothing else.
///
/// The role has its own storage key rather than riding in [AuthService]'s session: `verifySession()`
/// would silently downgrade a worker to client, and a guest can pick a role without registering.
class TicketsController extends ChangeNotifier {
  static const _roleKey = 'domix_job_role';

  final _storage = const FlutterSecureStorage();

  JobRole? _role;

  /// Null until a role has been chosen. The screen shows the chooser while it is null rather than
  /// guessing, because guessing puts somebody in the wrong half of a two-sided market.
  JobRole? get role => _role;

  List<WorkerProfile> get workers => DemoJobMarket.workers;

  final List<JobTicket> _myTickets = [...DemoJobMarket.myTickets];
  final List<JobTicket> _openTickets = [...DemoJobMarket.openTickets];

  /// The client's own tickets, newest first.
  List<JobTicket> get myTickets => List.unmodifiable(_myTickets);

  /// What a worker scrolls: every open job in the market.
  List<JobTicket> get openTickets => List.unmodifiable(_openTickets);

  /// What a shop owner scrolls: only the jobs whose client still has materials to buy. **The third
  /// role's whole reason to be here** - an owner is not hiring anybody.
  List<JobTicket> get materialTickets =>
      _openTickets.where((ticket) => ticket.needsMaterials).toList(growable: false);

  final Set<String> _respondedTo = {};

  /// A worker scrolling a feed needs to see which rows they have already touched, or they answer the
  /// same job twice.
  bool hasResponded(String ticketId) => _respondedTo.contains(ticketId);

  WorkerProfile _myProfile = DemoJobMarket.draftProfile;

  /// The анкета, and simultaneously the card a client would see. One object, so what is typed and what
  /// is read cannot drift.
  WorkerProfile get myProfile => _myProfile;

  /// Reads the stored role. Awaited in `main()` before the first frame: this decides which of three
  /// screens the Заявки tab is, and resolving it a frame late would show the chooser to somebody who
  /// chose a role months ago.
  Future<void> load() async {
    try {
      _role = JobRole.tryFromCode(await _storage.read(key: _roleKey));
      notifyListeners();
    } catch (_) {
      // corrupted or unreadable storage leaves the role null, which shows the chooser - the same "ask
      // rather than guess" the null default is for
    }
  }

  /// **Synchronous, with the write fired and forgotten.** A role change is a tab swap and the screen
  /// must not wait on the keystore to repaint; a failed write is worth exactly one re-pick on the next
  /// launch. Awaiting it made every caller a place a hung platform channel could stop the app dead.
  void setRole(JobRole role) {
    if (_role == role) return;
    _role = role;
    notifyListeners();
    unawaited(_storeRole(role));
  }

  Future<void> _storeRole(JobRole role) async {
    try {
      await _storage.write(key: _roleKey, value: role.code);
    } catch (_) {}
  }

  /// Back to the chooser, from the role pill in the tab's header.
  void clearRole() {
    _role = null;
    notifyListeners();
    unawaited(_forgetStoredRole());
  }

  /// Wrapped and awaited *inside* its own method rather than at the call sites: a bare `try/catch`
  /// around an un-awaited future catches nothing, because the failure arrives after the try block has
  /// returned - which turns a missing keystore into an unhandled rejection instead of a no-op.
  Future<void> _forgetStoredRole() async {
    try {
      await _storage.delete(key: _roleKey);
    } catch (_) {}
  }

  /// Puts the signed-in account's own name on the анкета. Called when the worker screen is opened
  /// rather than on login, because this controller must not import the auth one - `main()` owns the
  /// wiring between features.
  void setProfileName(String name) {
    if (name.isEmpty || _myProfile.name.ru == name) return;
    _myProfile = WorkerProfile(
      name: DemoText(name, name),
      skills: _myProfile.skills,
      experienceYears: _myProfile.experienceYears,
      priceFrom: _myProfile.priceFrom,
      district: _myProfile.district,
      about: _myProfile.about,
      rating: _myProfile.rating,
      reviews: _myProfile.reviews,
      availableNow: _myProfile.availableNow,
    );
    notifyListeners();
  }

  /// Posts a client's ticket, into their own list *and* the open feed, so switching to the worker role
  /// shows the job that was just posted. The text is stored as the same string in both languages: it
  /// was typed once, and inventing a translation would be worse than showing what they wrote.
  void addTicket({
    required String title,
    required String description,
    required JobCategory category,
    required int budgetFrom,
    required String district,
  }) {
    final ticket = JobTicket(
      id: 'own-${DateTime.now().microsecondsSinceEpoch}',
      title: DemoText(title, title),
      description: DemoText(description, description),
      category: category,
      budgetFrom: budgetFrom,
      district: DemoText(district, district),
      postedAgo: Duration.zero,
      authorName: const DemoText('Вы', 'Siz'),
      needsMaterials: true,
    );
    _myTickets.insert(0, ticket);
    _openTickets.insert(0, ticket);
    notifyListeners();
  }

  /// A worker offering on a job. Bumps the count the client sees, which is what makes the two roles
  /// look like one market rather than two unrelated lists.
  void respondTo(String ticketId) {
    if (!_respondedTo.add(ticketId)) return;
    _bumpResponses(_openTickets, ticketId);
    _bumpResponses(_myTickets, ticketId);
    notifyListeners();
  }

  void _bumpResponses(List<JobTicket> tickets, String ticketId) {
    final index = tickets.indexWhere((ticket) => ticket.id == ticketId);
    if (index == -1) return;
    tickets[index] = tickets[index].copyWith(responses: tickets[index].responses + 1);
  }

  void saveProfile({
    required List<JobCategory> skills,
    required int experienceYears,
    required int priceFrom,
    required String about,
    required bool availableNow,
  }) {
    _myProfile = _myProfile.copyWith(
      skills: skills,
      experienceYears: experienceYears,
      priceFrom: priceFrom,
      about: DemoText(about, about),
      availableNow: availableNow,
    );
    notifyListeners();
  }

  /// Wipes everything a session left behind: the role, the answers, the анкета and any ticket posted
  /// from this phone. **Privacy, not staleness** - a ticket is somebody's address and their budget.
  void handleSessionEnded() {
    _role = null;
    _respondedTo.clear();
    _myProfile = DemoJobMarket.draftProfile;
    _myTickets
      ..clear()
      ..addAll(DemoJobMarket.myTickets);
    _openTickets
      ..clear()
      ..addAll(DemoJobMarket.openTickets);
    notifyListeners();
    unawaited(_forgetStoredRole());
  }
}
