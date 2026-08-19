import 'package:flutter/material.dart';

import 'ocr_service.dart';

class Shift {
  String date;
  String type;
  String time;

  Shift({
    required this.date,
    required this.type,
    required this.time,
  });
}

class ReviewScreen extends StatefulWidget {
  final String selectedName;
  final RotaRow? rotaRow;

  const ReviewScreen({
    super.key,
    required this.selectedName,
    required this.rotaRow,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final List<Shift> shifts = [
    Shift(
      date: 'August 1',
      type: 'DAY',
      time: '07:00 → 19:00',
    ),
    Shift(
      date: 'August 2',
      type: 'NIGHT',
      time: '19:00 → 07:00',
    ),
    Shift(
      date: 'August 3',
      type: 'OFF',
      time: '',
    ),
    Shift(
      date: 'August 4',
      type: 'DAY',
      time: '07:00 → 19:00',
    ),
  ];

  void _editShift(int index) {
    final shift = shifts[index];

    final typeController = TextEditingController(
      text: shift.type,
    );

    final timeController = TextEditingController(
      text: shift.time,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(shift.date),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeController,
                decoration: const InputDecoration(
                  labelText: 'Shift type',
                ),
              ),
              TextField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Time',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  shift.type = typeController.text;
                  shift.time = timeController.text;
                });

                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _addToCalendar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Shifts added to calendar!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Your Rota'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Rota for ${widget.selectedName}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          if (widget.rotaRow != null) ...[
            Text(
              'Detected OCR cells: '
              '${widget.rotaRow!.cells.map((cell) => cell.text).join(' | ')}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
          ],

          const Text(
            'Check your shifts before adding them to your calendar.',
            style: TextStyle(
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 20),

          ...List.generate(
            shifts.length,
            (index) {
              final shift = shifts[index];

              return Card(
                margin: const EdgeInsets.only(
                  bottom: 12,
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.calendar_today,
                  ),
                  title: Text(shift.date),
                  subtitle: Text(
                    shift.time.isEmpty
                        ? shift.type
                        : '${shift.type}\n${shift.time}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      _editShift(index);
                    },
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _addToCalendar,
            icon: const Icon(Icons.calendar_month),
            label: const Text('Add to Calendar'),
          ),
        ],
      ),
    );
  }
}
