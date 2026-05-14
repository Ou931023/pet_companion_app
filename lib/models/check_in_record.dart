class CheckInRecord {
  const CheckInRecord({
    required this.checkInDates,
    required this.lastCheckInDate,
  });

  final Set<String> checkInDates;
  final String? lastCheckInDate;

  CheckInRecord copyWith({
    Set<String>? checkInDates,
    String? lastCheckInDate,
    bool clearLastCheckInDate = false,
  }) {
    return CheckInRecord(
      checkInDates: checkInDates ?? this.checkInDates,
      lastCheckInDate:
          clearLastCheckInDate ? null : lastCheckInDate ?? this.lastCheckInDate,
    );
  }

  factory CheckInRecord.initial() {
    return const CheckInRecord(checkInDates: <String>{}, lastCheckInDate: null);
  }
}
