import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'review_screen.dart';
import 'calendar_screen.dart';
import 'ocr_service.dart';

void main() {
  runApp(const ShiftSnapApp());
}

class ShiftSnapApp extends StatelessWidget {
  const ShiftSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShiftSnap',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

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

  // Stores every OCR element together with its position.
  List<OcrElement> _ocrElements = [];
  List<RotaRow> _rotaRows = [];
  RotaRow? _dateHeaderRow;
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
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (image == null) {
      return;
    }

    setState(() {
      _selectedImage = image;
      _recognizedText = '';
      _foundNames = [];
      _selectedName = null;
      _ocrElements = [];
      _rotaRows = [];
      _dateHeaderRow = null;
      _cellDateHeaders = {};
      _isProcessing = true;
    });

    try {
      final RotaData rotaData =
          await _ocrService.processRotaImage(image.path);

      setState(() {
        _recognizedText = rotaData.rawText;
        _foundNames = rotaData.names;
        _ocrElements = rotaData.elements;
        _rotaRows = rotaData.rows;
        _dateHeaderRow = rotaData.dateHeaderRow;
        _cellDateHeaders = rotaData.cellDateHeaders;

        if (_foundNames.isNotEmpty) {
          _selectedName = _foundNames.first;
        }

        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _recognizedText = 'OCR error: $e';
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
      _cellDateHeaders = {};
      _isProcessing = false;
    });
  }

  void _openReviewScreen() {
    if (_selectedName == null) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReviewScreen(
          selectedName: _selectedName!,
          rotaRow: _selectedRotaRow,
        ),
      ),
    );
  }

  void _openCalendarScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CalendarScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShiftSnap'),
        centerTitle: true,
      ),
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
        const Icon(
          Icons.calendar_month,
          size: 80,
          color: Colors.blue,
        ),

        const SizedBox(height: 20),

        const Text(
          'Import your rota in seconds',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
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
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
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

        // OCR is currently processing.
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

        // Show detected names.
        if (!_isProcessing && _foundNames.isNotEmpty) ...[
          const Text(
            'Select your name from the list:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
            ),
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
            items: _foundNames.map((name) {
              return DropdownMenuItem<String>(
                value: name,
                child: Text(name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedName = value;
              });
            },
          ),

          const SizedBox(height: 12),
        ],

        if (!_isProcessing && _selectedRotaRow != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.06),
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Selected row (left -> right)\n'
              'y=${_selectedRotaRow!.centerY.toStringAsFixed(1)}\n'
              '${_selectedRotaRow!.cells.map((cell) {
                final header = _cellDateHeaders[cell];
                final date = header == null ? '' : ' -> ${header.text}';
                return '${cell.text} [x:${cell.centerX.toStringAsFixed(0)}]$date';
              }).join('  |  ')}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),

        // DEBUG VIEW:
        // Shows every OCR element and its location.
        if (!_isProcessing && _ocrElements.isNotEmpty)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade400,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OCR Layout (grouped rows)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Expanded(
                    child: ListView.builder(
                      itemCount: _rotaRows.length,
                      itemBuilder: (context, index) {
                        final row = _rotaRows[index];
                        final headerMarker = identical(row, _dateHeaderRow)
                            ? '  ← date-header candidate'
                            : '';

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          child: Text(
                            '$row$headerMarker',
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
          ),

        // If OCR produced no elements, show the raw OCR text.
        if (!_isProcessing &&
            _ocrElements.isEmpty &&
            _recognizedText.isNotEmpty)
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade400,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _recognizedText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _removeImage,
              child: const Text('Choose Another'),
            ),

            const SizedBox(width: 12),

            ElevatedButton(
              onPressed:
                  _selectedName == null ? null : _openReviewScreen,
              child: const Text('Continue'),
            ),
          ],
        ),
      ],
    );
  }
}
