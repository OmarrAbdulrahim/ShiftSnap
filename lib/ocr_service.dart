import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models/rota_models.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<RotaData> processRotaImage(String imagePath) async {
    final recognizedText = await _textRecognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final elements = <OcrElement>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
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
    final names = rows
        .where((row) => row.employeeName != null)
        .map((row) => row.employeeName!)
        .toSet()
        .toList();
    final firstEmployeeY = rows
        .where((row) => row.employeeName != null)
        .map((row) => row.centerY)
        .fold<double?>(
          null,
          (lowest, y) => lowest == null || y < lowest ? y : lowest,
        );
    final headerElements = _findHeaderElements(
      rows,
      firstEmployeeY,
    ).expand(_splitDateHeaderElement).toList();
    final columns = _buildColumns(headerElements);
    final dateHeaders = headerElements
        .where(_containsDateToken)
        .toList(growable: false);
    final cellDateHeaders = <OcrElement, OcrElement>{};

    final mappedRows = rows.map((row) {
      if (row.employeeName == null || row.cells.isEmpty) return row;
      final expandedCells = <OcrElement>[row.cells.first];
      for (final cell in row.cells.skip(1)) {
        expandedCells.addAll(_splitShiftElement(cell));
      }
      return RotaRow(
        employeeName: row.employeeName,
        centerY: row.centerY,
        cells: List.unmodifiable(expandedCells),
      );
    }).toList();

    for (final row in mappedRows.where((row) => row.employeeName != null)) {
      for (final cell in row.cells.skip(1)) {
        final column = _columnForX(columns, cell.centerX);
        if (column == null) continue;
        cell.columnIndex = column.index;
        cell.columnX = column.centerX;
        cell.headerText = column.headerText;
        final dateElements = column.headerElements
            .where(_containsDateToken)
            .toList();
        final header = dateElements.isEmpty ? null : dateElements.first;
        if (header != null) cellDateHeaders[cell] = header;
      }
    }

    return RotaData(
      names: names,
      rawText: recognizedText.text,
      elements: elements,
      rows: mappedRows,
      dateHeaderRow: _findDateHeaderRow(rows, headerElements),
      dateHeaders: List.unmodifiable(dateHeaders),
      cellDateHeaders: Map.unmodifiable(cellDateHeaders),
      columns: List.unmodifiable(columns),
    );
  }

  List<OcrElement> _findHeaderElements(
    List<RotaRow> rows,
    double? firstEmployeeY,
  ) {
    final candidates = <OcrElement>[];
    for (final row in rows) {
      if (firstEmployeeY != null && row.centerY >= firstEmployeeY) continue;
      for (final element in row.cells) {
        if (_containsDateToken(element)) candidates.add(element);
      }
    }
    return candidates;
  }

  List<OcrElement> _splitDateHeaderElement(OcrElement element) {
    final matches = RegExp(
      r'(?:0?[1-9]|[12][0-9]|3[01])|(?:MON|TUE|WED|THU|FRI|SAT|SUN)',
      caseSensitive: false,
    ).allMatches(element.text).toList();
    if (matches.length <= 1) return [element];
    return [
      for (final match in matches)
        _subElement(element, match.group(0)!, match.start, match.end),
    ];
  }

  List<OcrElement> _splitShiftElement(OcrElement element) {
    final matches = RegExp(r'\S+').allMatches(element.text).toList();
    if (matches.length <= 1) return [element];
    return [
      for (final match in matches)
        _subElement(element, match.group(0)!, match.start, match.end),
    ];
  }

  OcrElement _subElement(OcrElement source, String text, int start, int end) {
    final length = source.text.length;
    final left = source.left + (source.right - source.left) * start / length;
    final right = source.left + (source.right - source.left) * end / length;
    return OcrElement(
      text: text,
      left: left,
      top: source.top,
      right: right,
      bottom: source.bottom,
    );
  }

  List<RotaColumn> _buildColumns(List<OcrElement> headers) {
    if (headers.isEmpty) return const [];

    final anchors = <int, OcrElement>{};
    for (final header in headers) {
      final match = RegExp(
        r'^(0?[1-9]|[12][0-9]|3[01])$',
      ).firstMatch(header.text.trim());
      final day = match == null ? null : int.tryParse(match.group(1)!);
      if (day != null) anchors.putIfAbsent(day, () => header);
    }

    final sorted = anchors.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in sorted)
        RotaColumn(
          index: entry.key,
          centerX: entry.value.centerX,
          headerText: entry.key.toString(),
          headerElements: [entry.value],
        ),
    ];
  }

  RotaColumn? _columnForX(List<RotaColumn> columns, double x) {
    if (columns.isEmpty) return null;

    RotaColumn? closest;
    double closestDistance = double.infinity;

    for (final column in columns) {
      final distance = (x - column.centerX).abs();

      if (distance < closestDistance) {
        closestDistance = distance;
        closest = column;
      }
    }

    // Don't attach an OCR cell to a column if it is obviously too far away.
    final spacing = columns.length > 1
        ? (columns[1].centerX - columns[0].centerX).abs()
        : 40.0;

    if (closestDistance > spacing * 0.5) {
      return null;
    }

    return closest;
  }

  RotaRow? _findDateHeaderRow(
    List<RotaRow> rows,
    List<OcrElement> headerElements,
  ) {
    if (headerElements.isEmpty) return null;
    final headerY = _averageY(headerElements);
    final candidates = rows
        .where((row) => row.cells.any(_containsDateToken))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) =>
          (a.centerY - headerY).abs().compareTo((b.centerY - headerY).abs()),
    );
    return candidates.first;
  }

  bool _containsDateToken(OcrElement element) {
    final value = element.text.trim().toUpperCase();
    return RegExp(r'\b(?:0?[1-9]|[12][0-9]|3[01])\b').hasMatch(value) ||
        RegExp(
          r'\b(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\b',
        ).hasMatch(value);
  }

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
      final tolerance = _maxOf([
        minimumTolerance,
        _averageHeight(cluster) * 0.8,
        element.height.abs() * 0.8,
      ]);
      if ((element.centerY - _averageY(cluster)).abs() <= tolerance) {
        cluster.add(element);
      } else {
        clusters.add([element]);
      }
    }
    return clusters.map((cluster) {
      cluster.sort((a, b) => a.left.compareTo(b.left));
      return RotaRow(
        employeeName: _employeeNameForRow(cluster),
        centerY: _averageY(cluster),
        cells: List.unmodifiable(cluster),
      );
    }).toList();
  }

  double _averageY(List<OcrElement> cells) =>
      cells.map((cell) => cell.centerY).reduce((a, b) => a + b) / cells.length;

  double _averageHeight(List<OcrElement> cells) =>
      cells.map((cell) => cell.height.abs()).reduce((a, b) => a + b) /
      cells.length;

  double _maxOf(List<double> values) =>
      values.reduce((current, next) => current > next ? current : next);

  String? _employeeNameForRow(List<OcrElement> cells) {
    final firstCell = cells.first;
    return _looksLikeName(firstCell.text) ? firstCell.text : null;
  }

  bool _looksLikeName(String text) {
    if (text.length < 3) return false;
    const excluded = {
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
    return !excluded.contains(text.toUpperCase()) &&
        RegExp(r'^[A-Z\s]+$').hasMatch(text);
  }

  void dispose() => _textRecognizer.close();
}
