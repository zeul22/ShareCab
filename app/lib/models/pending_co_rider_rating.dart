/// One co-rider this rider still needs to rate (or skip) on a recent
/// trip. Returned by `GET /api/ratings/pending` and consumed by the
/// rider app's auto-prompt: when the polling watcher sees the list
/// grow, it pops a [CoRiderRatingDialog] for each entry.
///
/// The list is filtered server-side to exclude (a) entries already
/// rated, (b) entries already skipped, and (c) trips older than 7d.
class PendingCoRiderRating {
  /// Trip from the current user's perspective — the leg they were the
  /// rider on. Used as the `tripId` in subsequent rate / skip calls.
  final String tripId;

  /// User id of the co-rider being prompted about.
  final String coRiderId;

  /// Display name for the prompt headline.
  final String coRiderName;

  /// Co-rider's current rating (denormalised on the User doc). Shown
  /// in the dialog so the rater has context before rating.
  final double coRiderRating;

  const PendingCoRiderRating({
    required this.tripId,
    required this.coRiderId,
    required this.coRiderName,
    required this.coRiderRating,
  });

  factory PendingCoRiderRating.fromJson(Map<String, dynamic> json) {
    return PendingCoRiderRating(
      tripId: (json['tripId'] as String?) ?? '',
      coRiderId: (json['coRiderId'] as String?) ?? '',
      coRiderName: (json['coRiderName'] as String?) ?? 'Co-rider',
      coRiderRating: ((json['coRiderRating'] as num?) ?? 5).toDouble(),
    );
  }

  /// Stable key for de-duping in collections. Same shape as the
  /// backend's uniqueness constraint on RatingSkip / Rating.
  String get key => '$tripId|$coRiderId';
}
