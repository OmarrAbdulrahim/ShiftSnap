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
    List<RotaRow> allRows = const [],
    String rawOcrText = '',
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
      allRows: allRows,
      rawOcrText: rawOcrText,
      referenceDate: rotaDate,
    );
    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const AiServiceException('Gemini returned no shift data.');
    }

    try {
      final shifts = _parseResponse(text, rotaDate);
      return _mergeShifts(shifts, localShifts);
    } on FormatException catch (error) {
      throw AiServiceException(
        'Gemini returned unusable JSON: ${error.message}',
        rawResponse: text,
      );
    } on Object {
      throw AiServiceException(
        'Gemini returned unusable JSON.',
        rawResponse: text,
      );
    }
  }

  List<ParsedShift> _parseResponse(String response, DateTime referenceDate) {
    final cleaned = _cleanJson(response);
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! List) {
        throw const FormatException('Expected a JSON array.');
      }
      return decoded.map((item) {
        if (item is! Map) throw const FormatException('Invalid shift item.');
        return ParsedShift.fromJson(Map<String, dynamic>.from(item));
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
    } on FormatException {
      final lines = RegExp(
        r'^\s*(0?[1-9]|[12][0-9]|3[01])\s*:\s*([A-Za-z0-9_-]+)\s*$',
        multiLine: true,
      ).allMatches(response).toList();
      if (lines.isEmpty) rethrow;
      final lastDay = DateTime(
        referenceDate.year,
        referenceDate.month + 1,
        0,
      ).day;
      return [
        for (final line in lines)
          if (int.parse(line.group(1)!) <= lastDay)
            ParsedShift(
              date: DateTime(
                referenceDate.year,
                referenceDate.month,
                int.parse(line.group(1)!),
              ),
              code: line.group(2)!.toUpperCase(),
              type: 'UNKNOWN',
              time: '',
            ),
      ];
    }
  }

  String _buildPrompt({
    required String employeeName,
    required RotaRow rotaRow,
    required List<OcrElement> dateHeaders,
    required Map<OcrElement, OcrElement> cellDateHeaders,
    required List<RotaRow> allRows,
    required String rawOcrText,
    required DateTime referenceDate,
  }) {
    final rowCells = rotaRow.cells.map((cell) {
      final header = cellDateHeaders[cell];
      return {
        'rawText': cell.text,
        'columnIndex': cell.columnIndex,
        'columnX': cell.columnX,
        'centerX': cell.centerX.round(),
        'centerY': cell.centerY.round(),
        'headerText': cell.headerText,
        'matchedHeader': header == null
            ? null
            : {'text': header.text, 'x': header.centerX.round()},
      };
    }).toList();
    final headers = dateHeaders
        .map((header) => {'text': header.text, 'x': header.centerX.round()})
        .toList();
    final rows = allRows
        .map((row) => row.cells.map((cell) => cell.text).join(' | '))
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
Other OCR rows (may contain a legend): ${jsonEncode(rows)}
Raw OCR text: $rawOcrText

Return ONLY a JSON array. Each item must exactly have:
{"date":"YYYY-MM-DD","code":"raw OCR code","type":"UNKNOWN","time":"HH:mm - HH:mm"}

If a legend is visible in the supplied OCR, use it. Otherwise do not assume
that A, B, C, DO, or any other code has a universal meaning. Preserve the raw
code and return type UNKNOWN with an empty time when the meaning is unknown.
Only return a shift when its header provides a full unambiguous date. Include
the original code in a `code` field for every item.
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
    final lastDay = DateTime(
      referenceDate.year,
      referenceDate.month + 1,
      0,
    ).day;
    for (final cell in rotaRow.cells) {
      final header = cellDateHeaders[cell];
      final day = header == null ? null : _fullDate(header.text);
      if (day == null ||
          day.month != referenceDate.month ||
          day.day > lastDay) {
        continue;
      }
      final code = cell.text.trim().toUpperCase();
      if (!_universalShiftCode(code)) continue;

      shifts.add(ParsedShift(date: day, code: code, type: 'UNKNOWN', time: ''));
    }
    return shifts..sort((a, b) => a.date.compareTo(b.date));
  }

  DateTime? _fullDate(String value) {
    final iso = RegExp(
      r'\b(20\d{2})[-/]([01]?\d)[-/]([0-3]?\d)\b',
    ).firstMatch(value);
    if (iso != null) {
      return DateTime.tryParse(
        '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}',
      );
    }
    return null;
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
    return merged.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  String _shiftKey(ParsedShift shift) {
    final date = shift.date.toIso8601String().substring(0, 10);
    return '$date:${shift.code.isEmpty ? shift.type : shift.code}';
  }

  bool _universalShiftCode(String value) {
    final code = value.trim().toUpperCase();
    return RegExp(r'^[A-Z0-9]{1,4}$').hasMatch(code) &&
        !{'NAME', 'TOTAL', 'ROTA'}.contains(code);
  }

  String _cleanJson(String value) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start >= 0 && end >= start) {
      cleaned = cleaned.substring(start, end + 1);
    }
    return cleaned.trim();
  }
}

class AiServiceException implements Exception {
  final String message;
  final String? rawResponse;

  const AiServiceException(this.message, {this.rawResponse});

  @override
  String toString() => message;
}
