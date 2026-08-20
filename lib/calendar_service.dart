import 'package:add_2_calendar/add_2_calendar.dart';

import 'models/rota_models.dart';

class CalendarExportResult {
  final int exported;
  final int skipped;

  const CalendarExportResult({required this.exported, required this.skipped});
}

class CalendarService {
  Future<CalendarExportResult> exportShifts({
    required String employeeName,
    required Iterable<ParsedShift> shifts,
  }) async {
    var exported = 0;
    var skipped = 0;

    for (final shift in shifts) {
      final range = shift.dateTimeRange;
      if (range == null) {
        skipped++;
        continue;
      }

      final wasAdded = await Add2Calendar.addEvent2Cal(
        Event(
          title: '$employeeName - ${shift.type} shift',
          description: 'Created by ShiftSnap',
          startDate: range.start,
          endDate: range.end,
        ),
      );
      if (wasAdded) {
        exported++;
      } else {
        skipped++;
      }
    }

    return CalendarExportResult(exported: exported, skipped: skipped);
  }
}
