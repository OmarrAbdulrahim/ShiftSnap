import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../calendar_screen.dart';
import '../models/rota_models.dart';
import '../ocr_service.dart';
import '../review_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocrService = OcrService();

  XFile? _selectedImage;
  String _recognizedText = '';
  bool _isProcessing = false;
  List<String> _foundNames = [];
  String? _selectedName;
  List<OcrElement> _ocrElements = [];
  List<RotaRow> _rotaRows = [];
  RotaRow? _dateHeaderRow;
  List<OcrElement> _dateHeaders = [];
  Map<OcrElement, OcrElement> _cellDateHeaders = {};

  RotaRow? get _selectedRotaRow {
    final selectedName = _selectedName;
    if (selectedName == null) return null;
    for (final row in _rotaRows) {
      if (row.employeeName == selectedName) return row;
    }
    return null;
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _scanRota() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _selectedImage = image;
      _recognizedText = '';
      _foundNames = [];
      _selectedName = null;
      _ocrElements = [];
      _rotaRows = [];
      _dateHeaderRow = null;
      _dateHeaders = [];
      _cellDateHeaders = {};
      _isProcessing = true;
    });

    try {
      final rotaData = await _ocrService.processRotaImage(image.path);
      setState(() {
        _recognizedText = rotaData.rawText;
        _foundNames = rotaData.names;
        _ocrElements = rotaData.elements;
        _rotaRows = rotaData.rows;
        _dateHeaderRow = rotaData.dateHeaderRow;
        _dateHeaders = rotaData.dateHeaders;
        _cellDateHeaders = rotaData.cellDateHeaders;
        _selectedName = _foundNames.isEmpty ? null : _foundNames.first;
        _isProcessing = false;
      });
    } catch (error) {
      setState(() {
        _isProcessing = false;
        _recognizedText = 'OCR error: $error';
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _recognizedText = '';
      _foundNames = [];
      _selectedName = null;
      _ocrElements = [];
      _rotaRows = [];
      _dateHeaderRow = null;
      _dateHeaders = [];
      _cellDateHeaders = {};
      _isProcessing = false;
    });
  }

  void _openReviewScreen() {
    final selectedName = _selectedName;
    if (selectedName == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewScreen(
          selectedName: selectedName,
          rotaRow: _selectedRotaRow,
          dateHeaders: _dateHeaders,
          cellDateHeaders: _cellDateHeaders,
          allRows: _rotaRows,
          rawOcrText: _recognizedText,
        ),
      ),
    );
  }

  void _openCalendarScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CalendarScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShiftSnap'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: _selectedImage == null
              ? _buildHomeContent()
              : _buildImagePreview(),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.calendar_month, size: 80, color: Colors.blue),
        const SizedBox(height: 20),
        const Text(
          'Import your rota in seconds',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _scanRota,
          icon: const Icon(Icons.upload_file),
          label: const Text('Scan Rota'),
        ),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: _openCalendarScreen,
          icon: const Icon(Icons.calendar_month),
          label: const Text('My Calendar'),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Rota Selected',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              File(_selectedImage!.path),
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isProcessing)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text('Reading your rota...'),
              ],
            ),
          ),
        if (!_isProcessing && _foundNames.isNotEmpty) ...[
          const Text(
            'Select your name from the list:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedName,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: _foundNames
                .map(
                  (name) =>
                      DropdownMenuItem<String>(value: name, child: Text(name)),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedName = value),
          ),
          const SizedBox(height: 12),
        ],
        if (!_isProcessing && _selectedRotaRow != null) _buildSelectedRow(),
        if (!_isProcessing && _ocrElements.isNotEmpty) _buildOcrLayout(),
        if (!_isProcessing &&
            _ocrElements.isEmpty &&
            _recognizedText.isNotEmpty)
          _buildRawText(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _removeImage,
              child: const Text('Choose Another'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _selectedName == null ? null : _openReviewScreen,
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedRow() {
    final row = _selectedRotaRow!;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        border: Border.all(color: Colors.blue.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Selected row (left -> right)\n'
        'y=${row.centerY.toStringAsFixed(1)}\n'
        '${row.cells.map((cell) {
          final header = _cellDateHeaders[cell];
          final date = header == null ? '' : ' -> ${header.text}';
          return '${cell.text} [x:${cell.centerX.toStringAsFixed(0)}]$date';
        }).join('  |  ')}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _buildOcrLayout() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OCR Layout (grouped rows)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _rotaRows.length,
                itemBuilder: (context, index) {
                  final row = _rotaRows[index];
                  final marker = identical(row, _dateHeaderRow)
                      ? '  <- date-header candidate'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '$row$marker',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRawText() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          child: Text(
            _recognizedText,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}
