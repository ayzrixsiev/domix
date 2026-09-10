import 'dart:ui';

import 'package:frontend/core/constants/app_colors.dart';
import 'package:frontend/core/localization/app_localizations.dart';
import 'package:frontend/features/tickets/data/job_category.dart';

/// A string that exists in both app languages at once. **Only the seeded demo market uses this, and
/// that is the whole reason it is allowed to exist**: fixtures are not copy, and thirty names would
/// mean thirty getters in the localization file for text nobody reads twice.
class DemoText {
  const DemoText(this.ru, this.uz);

  final String ru;
  final String uz;

  String of(AppLocalizations strings) => strings.isRu ? ru : uz;
}

/// Three states, because three is what a client can act on: nobody has come yet, somebody is doing
/// it, it is finished.
enum TicketStatus {
  searching,
  inProgress,
  done;

  String label(AppLocalizations strings) => switch (this) {
        TicketStatus.searching => strings.ticketStatusSearching,
        TicketStatus.inProgress => strings.ticketStatusInProgress,
        TicketStatus.done => strings.ticketStatusDone,
      };

  /// text colour and its own tint behind it, from the same token pairs the price-tier badge uses - so
  /// a status here and a price there read as the same family of signal
  (Color foreground, Color background) get colors => switch (this) {
        TicketStatus.searching => (AppColors.warning, AppColors.warningSoft),
        TicketStatus.inProgress => (AppColors.accentBlue, AppColors.primarySoft),
        TicketStatus.done => (AppColors.success, AppColors.successSoft),
      };
}

/// One job a client is asking for. [postedAgo] is a duration rather than a timestamp: these are
/// fixtures, and a fixed `DateTime` would read «2 часа назад» when written and «213 дней назад» at
/// the demo.
class JobTicket {
  const JobTicket({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.budgetFrom,
    required this.district,
    required this.postedAgo,
    required this.authorName,
    this.responses = 0,
    this.status = TicketStatus.searching,
    this.needsMaterials = false,
  });

  final String id;
  final DemoText title;
  final DemoText description;
  final JobCategory category;

  /// a floor rather than a range: a single number is what a worker scanning a feed can compare, and
  /// every range in a feed like this is read as its lower bound anyway
  final int budgetFrom;

  final DemoText district;
  final Duration postedAgo;
  final DemoText authorName;

  /// the one number that tells a client their ticket is alive, and a worker how much competition they
  /// are walking into
  final int responses;

  final TicketStatus status;

  /// Whether the job needs materials bought, which is what puts it in a shop owner's feed. **The third
  /// role's entire filter**: an owner has no interest in who lays the tile, only in the fact that
  /// somebody is about to buy two hundred square metres of it.
  final bool needsMaterials;

  JobTicket copyWith({int? responses, TicketStatus? status}) => JobTicket(
        id: id,
        title: title,
        description: description,
        category: category,
        budgetFrom: budgetFrom,
        district: district,
        postedAgo: postedAgo,
        authorName: authorName,
        responses: responses ?? this.responses,
        status: status ?? this.status,
        needsMaterials: needsMaterials,
      );
}

/// A worker as a client sees them, and as the worker fills them in on their own анкета. **One class
/// for both**: the анкета is a preview of the card, and modelling the two separately is how a form
/// ends up collecting a field the card never shows.
class WorkerProfile {
  const WorkerProfile({
    required this.name,
    required this.skills,
    required this.experienceYears,
    required this.priceFrom,
    required this.district,
    required this.about,
    this.rating = 0,
    this.reviews = 0,
    this.availableNow = true,
  });

  final DemoText name;

  /// most important first. a list rather than one value because a finisher who also tiles is the
  /// normal case here, and forcing that person to pick one makes them invisible in half the searches
  final List<JobCategory> skills;

  final int experienceYears;

  /// day rate floor, in so'm.
  final int priceFrom;

  final DemoText district;
  final DemoText about;

  final double rating;

  /// zero means "nobody has hired them through Domix yet", which the card says in words rather than
  /// showing 0.0 next to a star - an unrated worker is new, not bad
  final int reviews;

  final bool availableNow;

  bool get isNew => reviews == 0;

  WorkerProfile copyWith({
    List<JobCategory>? skills,
    int? experienceYears,
    int? priceFrom,
    DemoText? about,
    bool? availableNow,
  }) =>
      WorkerProfile(
        name: name,
        skills: skills ?? this.skills,
        experienceYears: experienceYears ?? this.experienceYears,
        priceFrom: priceFrom ?? this.priceFrom,
        district: district,
        about: about ?? this.about,
        rating: rating,
        reviews: reviews,
        availableNow: availableNow ?? this.availableNow,
      );
}
