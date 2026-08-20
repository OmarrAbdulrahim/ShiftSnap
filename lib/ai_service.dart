import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'models/rota_models.dart';

/// Converts OCR layout data into reviewed shift candidates.
///
/// Supply the key only at build/run time, e.g.
/// `flutter run --dart-define=GEMINI_API_KEY=...`. This deliberately avoids
/// placing credentials in source control or the APK configuration files.
class AiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<List<ParsedShift>> interpretRota({
    required String employeeName,
    required RotaRow rotaRow,
    required List<OcrElement> dateHeaders,
    required Map<OcrElement, OcrElement> cellDateHeaders,
    DateTime? referenceDate,
  }) async {
    final rotaDate = referenceDate ?? DateTime.now();
    final localShifts = _interpretKnownShiftCodes(
      rotaRow: rotaRow,
      dateHeaders: dateHeaders,
      cellDateHeaders: cellDateHeaders,
      referenceDate: rotaDate,
    );

    if (!isConfigured) {
      if (localShifts.isNotEmpty) return localShifts;
      throw const AiServiceException(
        'Gemini is not configured. Start the app with GEMINI_API_KEY to use AI interpretation.',
      );
    }

    final model = GenerativeModel(
      model: 'gemini-3.6-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.1,
        maxOutputTokens: 4096,
      ),
    );

    final prompt = _buildPrompt(
      employeeName: employeeName,
      rotaRow: rotaRow,
      dateHeaders: dateHeaders,
      cellDateHeaders: cellDateHeaders,
      referenceDate: rotaDate,
    );
    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const AiServiceException('Gemini returned no shift data.');
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        throw const FormatException('Expected a JSON array.');
      }
      final shifts = decoded.map((item) {
        if (item is! Map) throw const FormatException('Invalid shift item.');
        return ParsedShift.fromJson(Map<String, dynamic>.from(item));
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
      return _mergeShifts(shifts, localShifts);
    } on FormatException catch (error) {
      throw AiServiceException(
        'Gemini returned unusable JSON: ${error.message}',
      );
    } on Object {
      throw const AiServiceException('Gemini returned unusable JSON.');
    }
  }

  String _buildPrompt({
    required String employeeName,
    required RotaRow rotaRow,
    required List<OcrElement> dateHeaders,
    required Map<OcrElement, OcrElement> cellDateHeaders,
    required DateTime referenceDate,
  }) {
    final rowCells = rotaRow.cells.map((cell) {
      final header = cellDateHeaders[cell];
      return {
        'text': cell.text,
        'x': cell.centerX.round(),
        'y': cell.centerY.round(),
        'matchedHeader': header == null
            ? null
            : {'text': header.text, 'x': header.centerX.round()},
      };
    }).toList();
    final headers = dateHeaders
        .map((header) => {'text': header.text, 'x': header.centerX.round()})
        .toList();

    return '''
You interpret a single employee's work rota from OCR layout data. The OCR row
and header-column matches below are structured inputs; use their x coordinates
and matched header text to associate cells with dates. The rota reference month
is ${referenceDate.year}-${referenceDate.month.toString().padLeft(2, '0')}. Use
that year and month for a header containing only a day number, or a weekday and
day number. Do not invent a date outside the header columns.

Employee: $employeeName
Date/header cells: ${jsonEncode(headers)}
Selected employee row: ${jsonEncode(rowCells)}

Return ONLY a JSON array. Each item must exactly have:
{"date":"YYYY-MM-DD","type":"DAY/NIGHT/OFF/LEAVE","time":"HH:mm - HH:mm"}

Interpret common codes where supported by the layout/context: DO means OFF,
AL means LEAVE, OFF means OFF, DAY means DAY, and NIGHT means NIGHT. If a rota
legend is visible, it overrides defaults and defines the meaning of every code.
If no legend is visible, use this common convention: A means MORNING, B means
EVENING, and C means NIGHT. Preserve other short letter codes as their code in
the type field rather than dropping the shift; use an empty time when no time
is available. Include every supported header/cell pair as a full ISO date.
''';
  }

  List<ParsedShift> _interpretKnownShiftCodes({
    required RotaRow rotaRow,
    required List<OcrElement> dateHeaders,
    required Map<OcrElement, OcrElement> cellDateHeaders,
    required DateTime referenceDate,
  }) {
    if (dateHeaders.isEmpty) return const [];

    final shifts = <ParsedShift>[];
    final lastDay = DateTime(referenceDate.year, referenceDate.month + 1, 0)
        .day;
    for (final cell in rotaRow.cells) {
      final header = cellDateHeaders[cell];
      final day = header == null ? null : _dayNumber(header.text);
      if (day == null || day > lastDay) continue;

      final type = switch (cell.text.trim().toUpperCase()) {
        'DO' || 'OFF' => 'OFF',
        'AL' || 'LEAVE' => 'LEAVE',
        'DAY' => 'DAY',
        'NIGHT' => 'NIGHT',
        'A' => 'MORNING',
        'B' => 'EVENING',
        'C' => 'NIGHT',
        _ => _universalShiftCode(cell.text),
      };
      if (type == null) continue;

      shifts.add(
        ParsedShift(
          date: DateTime(referenceDate.year, referenceDate.month, day),
          type: type,
          time: '',
        ),
      );
    }
    return shifts..sort((a, b) => a.date.compareTo(b.date));
  }

  int? _dayNumber(String value) {
    final match = RegExp(r'\b(0?[1-9]|[12][0-9]|3[01])\b').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  List<ParsedShift> _mergeShifts(
    List<ParsedShift> interpreted,
    List<ParsedShift> local,
  ) {
    final merged = <String, ParsedShift>{
      for (final shift in local) _shiftKey(shift): shift,
    };
    for (final shift in interpreted) {
      merged[_shiftKey(shift)] = shift;
    }
    return merged.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  String _shiftKey(ParsedShift shift) {
    final date = shift.date.toIso8601String().substring(0, 10);
    return '$date:${shift.type}';
  }

  String? _universalShiftCode(String value) {
    final code = value.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{1,3}$').hasMatch(code) &&
        !{'NAME', 'TOTAL', 'ROTA'}.contains(code)) {
      return code;
    }
    return null;
  }
}

class AiServiceException implements Exception {
  final String message;

  const AiServiceException(this.message);

  @override
  String toString() => message;
}
