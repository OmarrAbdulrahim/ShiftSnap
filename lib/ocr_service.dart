import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

/// A horizontal OCR row, with cells in left-to-right order.
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

class OcrService {
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<RotaData> processRotaImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    final recognizedText =
        await _textRecognizer.processImage(inputImage);

    final List<OcrElement> elements = [];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();

        if (text.isEmpty) {
          continue;
        }

        final box = line.boundingBox;

        elements.add(
          OcrElement(
            text: text,
            left: box.left,
            top: box.top,
            right: box.right,
            bottom: box.bottom,
          ),
        );

      }
    }

    final rows = _groupIntoRows(elements);
    final detectedNames = rows
        .where((row) => row.employeeName != null)
        .map((row) => row.employeeName!)
        .toSet()
        .toList();

    final dateHeaderRow = _findDateHeaderRow(rows);
    final dateHeaders = dateHeaderRow == null
        ? <OcrElement>[]
        : dateHeaderRow.cells.where(_looksLikeDateHeader).toList();

    return RotaData(
      names: detectedNames,
      rawText: recognizedText.text,
      elements: elements,
      rows: rows,
      dateHeaderRow: dateHeaderRow,
      dateHeaders: List.unmodifiable(dateHeaders),
      cellDateHeaders: _matchCellsToDateHeaders(rows, dateHeaders),
    );
  }

  /// Associates each non-name cell in an employee row with its closest date
  /// header by X position. No shift code or time interpretation happens here.
  Map<OcrElement, OcrElement> _matchCellsToDateHeaders(
    List<RotaRow> rows,
    List<OcrElement> dateHeaders,
  ) {
    if (dateHeaders.isEmpty) return const {};

    final matches = <OcrElement, OcrElement>{};
    for (final row in rows) {
      if (row.employeeName == null) continue;
      for (final cell in row.cells.skip(1)) {
        final nearestHeader = dateHeaders.reduce((closest, header) {
          final isHeaderCloser =
              (cell.centerX - header.centerX).abs() <
                  (cell.centerX - closest.centerX).abs();
          return isHeaderCloser ? header : closest;
        });
        matches[cell] = nearestHeader;
      }
    }
    return Map.unmodifiable(matches);
  }

  /// Groups OCR lines by vertical centre. The tolerance derives from median
  /// line height, so this scales to different image resolutions and font sizes.
  List<RotaRow> _groupIntoRows(List<OcrElement> elements) {
    if (elements.isEmpty) return const [];

    final sorted = [...elements]
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final heights = sorted.map((element) => element.height.abs()).toList()
      ..sort();
    final medianHeight = heights[heights.length ~/ 2];
    final minimumTolerance = medianHeight > 0 ? medianHeight * 0.65 : 8.0;
    final clusters = <List<OcrElement>>[];

    for (final element in sorted) {
      if (clusters.isEmpty) {
        clusters.add([element]);
        continue;
      }

      final cluster = clusters.last;
      final rowCenter = _averageCenterY(cluster);
      final averageHeight = cluster
              .map((cell) => cell.height.abs())
              .reduce((a, b) => a + b) /
          cluster.length;
      final tolerance = _maxOf([
        minimumTolerance,
        averageHeight * 0.8,
        element.height.abs() * 0.8,
      ]);

      if ((element.centerY - rowCenter).abs() <= tolerance) {
        cluster.add(element);
      } else {
        clusters.add([element]);
      }
    }

    return clusters.map((cluster) {
      cluster.sort((a, b) => a.left.compareTo(b.left));
      return RotaRow(
        employeeName: _employeeNameForRow(cluster),
        centerY: _averageCenterY(cluster),
        cells: List.unmodifiable(cluster),
      );
    }).toList();
  }

  double _averageCenterY(List<OcrElement> cells) =>
      cells.map((cell) => cell.centerY).reduce((a, b) => a + b) /
      cells.length;

  double _maxOf(List<double> values) =>
      values.reduce((current, next) => current > next ? current : next);

  String? _employeeNameForRow(List<OcrElement> cells) {
    // Employee names normally occupy the first column. Limiting the test to
    // that left-most cell prevents all-caps shift codes becoming names.
    final firstCell = cells.first;
    return _looksLikeName(firstCell.text) ? firstCell.text : null;
  }

  RotaRow? _findDateHeaderRow(List<RotaRow> rows) {
    RotaRow? bestRow;
    var bestDateLikeCount = 0;
    for (final row in rows) {
      final count = row.cells.where(_looksLikeDateHeader).length;
      if (count >= 2 && count > bestDateLikeCount) {
        bestRow = row;
        bestDateLikeCount = count;
      }
    }
    return bestRow;
  }

  bool _looksLikeDateHeader(OcrElement cell) {
    final value = cell.text.trim().toUpperCase();
    if (RegExp(r'^(?:0?[1-9]|[12][0-9]|3[01])$').hasMatch(value)) {
      return true;
    }
    const weekday = r'(?:MON|TUE|WED|THU|FRI|SAT|SUN)';
    const day = r'(?:0?[1-9]|[12][0-9]|3[01])';
    return RegExp('^(?:${weekday}\\s*${day}|${day}\\s*${weekday})\$')
        .hasMatch(value);
  }

  bool _looksLikeName(String text) {
    if (text.length < 3) return false;

    const excludedWords = {
      'SAT',
      'SUN',
      'MON',
      'TUE',
      'WED',
      'THU',
      'FRI',
      'LAB',
      'DUTY',
      'ROTA',
      'DAY',
      'NIGHT',
      'OFF',
      'LEAVE',
      'ANNUAL',
      'MONTH',
      'TOTAL',
      'NAME',
    };

    if (excludedWords.contains(text.toUpperCase())) {
      return false;
    }

    return RegExp(r'^[A-Z\s]+$').hasMatch(text);
  }

  void dispose() {
    _textRecognizer.close();
  }
}
