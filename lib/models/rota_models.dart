import 'package:flutter/material.dart';

class OcrElement {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  OcrElement({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;

  @override
  String toString() {
    return '$text '
        '(x:${left.toStringAsFixed(0)}, '
        'y:${top.toStringAsFixed(0)})';
  }
}

class RotaRow {
  final String? employeeName;
  final double centerY;
  final List<OcrElement> cells;

  const RotaRow({
    required this.employeeName,
    required this.centerY,
    required this.cells,
  });

  @override
  String toString() {
    final name = employeeName ?? 'unnamed';
    return '$name (y:${centerY.toStringAsFixed(0)}): '
        '${cells.map((cell) => cell.text).join(' | ')}';
  }
}

class RotaData {
  final List<String> names;
  final String rawText;
  final List<OcrElement> elements;
  final List<RotaRow> rows;
  final RotaRow? dateHeaderRow;
  final List<OcrElement> dateHeaders;
  final Map<OcrElement, OcrElement> cellDateHeaders;

  RotaData({
    required this.names,
    required this.rawText,
    required this.elements,
    required this.rows,
    required this.dateHeaderRow,
    required this.dateHeaders,
    required this.cellDateHeaders,
  });
}

/// A reviewed shift ready for calendar export. `time` remains editable text so
/// a user can correct ambiguous rota conventions before export.
class ParsedShift {
  DateTime date;
  String type;
  String time;

  ParsedShift({required this.date, required this.type, required this.time});

  factory ParsedShift.fromJson(Map<String, dynamic> json) {
    final dateValue = json['date'];
    final typeValue = json['type'];
    final timeValue = json['time'];
    if (dateValue is! String || typeValue is! String || timeValue is! String) {
      throw const FormatException(
        'Each shift needs date, type, and time strings.',
      );
    }

    final date = DateTime.tryParse(dateValue);
    if (date == null) {
      throw FormatException('Invalid shift date: $dateValue');
    }

    return ParsedShift(
      date: DateTime(date.year, date.month, date.day),
      type: typeValue.trim().toUpperCase(),
      time: timeValue.trim(),
    );
  }

  bool get isNonWorking {
    final normalized = type.toUpperCase();
    return normalized == 'OFF' ||
        normalized == 'DAY OFF' ||
        normalized == 'DO' ||
        normalized == 'LEAVE' ||
        normalized == 'ANNUAL LEAVE' ||
        normalized == 'AL';
  }

  DateTimeRange? get dateTimeRange {
    if (isNonWorking) return null;
    final times = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(?:-|–|—|to)\s*(\d{1,2}):(\d{2})$',
      caseSensitive: false,
    ).firstMatch(time);
    if (times == null) return null;

    final startHour = int.tryParse(times.group(1)!);
    final startMinute = int.tryParse(times.group(2)!);
    final endHour = int.tryParse(times.group(3)!);
    final endMinute = int.tryParse(times.group(4)!);
    if ([
          startHour,
          startMinute,
          endHour,
          endMinute,
        ].any((value) => value == null) ||
        startHour! > 23 ||
        endHour! > 23 ||
        startMinute! > 59 ||
        endMinute! > 59) {
      return null;
    }

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startHour,
      startMinute,
    );
    var end = DateTime(date.year, date.month, date.day, endHour, endMinute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return DateTimeRange(start: start, end: end);
  }
}
