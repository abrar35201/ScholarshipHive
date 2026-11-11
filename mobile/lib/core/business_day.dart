/// The attendance business-day boundary is 7 AM, not midnight — matching the
/// backend's DateTimeExtensions.PakistanToday. An employee on an overnight
/// shift (5 PM to 2 AM) shouldn't see every admin screen roll over to a new
/// calendar date the moment the clock ticks past midnight while they're
/// still checked in against what the server still considers YESTERDAY's
/// business day; without this, "today" on screens like the Attendance tab
/// would silently disagree with what the server is actually showing/logging
/// data against until 7 AM caught up.
///
/// Device local time is assumed to already be Pakistan time (every real
/// user of this app is in Pakistan), so this only needs to shift the clock
/// back by the rollover hour, not also convert timezones.
DateTime businessToday() {
  final shifted = DateTime.now().subtract(const Duration(hours: 7));
  return DateTime(shifted.year, shifted.month, shifted.day);
}
