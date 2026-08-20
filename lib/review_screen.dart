import 'package:flutter/material.dart';

import 'ai_service.dart';
import 'calendar_service.dart';
import 'models/rota_models.dart';

class ReviewScreen extends StatefulWidget {
  final String selectedName;
  final RotaRow? rotaRow;
  final List<OcrElement> dateHeaders;
  final Map<OcrElement, OcrElement> cellDateHeaders;

  const ReviewScreen({
    super.key,
    required this.selectedName,
    required this.rotaRow,
    required this.dateHeaders,
    required this.cellDateHeaders,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final AiService _aiService = AiService();
  final CalendarService _calendarService = CalendarService();
  final List<ParsedShift> _shifts = [];

  bool _isInterpreting = true;
  bool _isExporting = false;
  String? _interpretationError;
  bool _showManualFallback = false;

  @override
  void initState() {
    super.initState();
    _interpretRota();
  }

  Future<void> _interpretRota() async {
    final row = widget.rotaRow;
    if (row == null) {
      setState(() {
        _isInterpreting = false;
        _interpretationError = 'No employee row was found in this scan.';
        _showManualFallback = true;
      });
      return;
    }

    try {
      final shifts = await _aiService.interpretRota(
        employeeName: widget.selectedName,
        rotaRow: row,
        dateHeaders: widget.dateHeaders,
        cellDateHeaders: widget.cellDateHeaders,
      );
      if (!mounted) return;
      setState(() {
        _shifts
          ..clear()
          ..addAll(shifts);
        _isInterpreting = false;
        _showManualFallback = shifts.isEmpty;
        _interpretationError = shifts.isEmpty
            ? 'No full dates could be safely interpreted from this rota.'
            : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isInterpreting = false;
        _interpretationError = error.toString();
        _showManualFallback = true;
      });
    }
  }

  Future<void> _editShift([ParsedShift? existing]) async {
    final shift =
        existing ??
        ParsedShift(date: DateTime.now(), type: 'DAY', time: '07:00 - 19:00');
    final typeController = TextEditingController(text: shift.type);
    final timeController = TextEditingController(text: shift.time);
    var selectedDate = shift.date;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add shift' : 'Edit shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(_formatDate(selectedDate)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) setDialogState(() => selectedDate = date);
                },
              ),
              TextField(
                controller: typeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Shift type'),
              ),
              TextField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: '07:00 - 19:00 (empty for OFF/LEAVE)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    setState(() {
      shift
        ..date = selectedDate
        ..type = typeController.text.trim().toUpperCase()
        ..time = timeController.text.trim();
      if (existing == null) _shifts.add(shift);
      _shifts.sort((a, b) => a.date.compareTo(b.date));
    });
  }

  Future<void> _addToCalendar() async {
    if (_shifts.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final result = await _calendarService.exportShifts(
        employeeName: widget.selectedName,
        shifts: _shifts,
      );
      if (!mounted) return;
      final message = result.exported == 0
          ? 'No exportable shifts. Add valid times such as 07:00 - 19:00.'
          : '${result.exported} calendar event${result.exported == 1 ? '' : 's'} opened for export.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Calendar export failed: $error')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Your Rota')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Rota for ${widget.selectedName}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review every shift before exporting it to your calendar.',
          ),
          const SizedBox(height: 20),
          if (_isInterpreting)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Interpreting your structured rota…'),
                ],
              ),
            )
          else ...[
            if (_interpretationError != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'AI interpretation unavailable: $_interpretationError\n'
                    'You can add the shifts manually below.',
                  ),
                ),
              ),
            if (_showManualFallback) _buildManualOcrHelp(),
            if (_shifts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No reviewed shifts yet. Add one manually.'),
              ),
            ..._shifts.map(_buildShiftCard),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _editShift(),
              icon: const Icon(Icons.add),
              label: const Text('Add shift manually'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _shifts.isEmpty || _isExporting
                  ? null
                  : _addToCalendar,
              icon: _isExporting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_month),
              label: Text(_isExporting ? 'Exporting…' : 'Add to Calendar'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftCard(ParsedShift shift) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(shift.isNonWorking ? Icons.event_busy : Icons.event),
      title: Text(_formatDate(shift.date)),
      subtitle: Text(
        shift.time.isEmpty ? shift.type : '${shift.type}\n${shift.time}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () => _editShift(shift),
      ),
    ),
  );

  Widget _buildManualOcrHelp() {
    final row = widget.rotaRow;
    if (row == null) return const SizedBox.shrink();
    final cells = row.cells.skip(row.employeeName == null ? 0 : 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'OCR cells available for manual entry:\n${cells.map((cell) {
            final header = widget.cellDateHeaders[cell];
            return '${cell.text}${header == null ? '' : ' (header: ${header.text})'}';
          }).join(' | ')}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
