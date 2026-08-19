import 'package:flutter/material.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Shifts'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'August 2026',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          _shift(
            'Sat, Aug 1',
            'DAY',
            '07:00 → 19:00',
          ),

          _shift(
            'Sun, Aug 2',
            'NIGHT',
            '19:00 → 07:00',
          ),

          _shift(
            'Mon, Aug 3',
            'OFF',
            '',
          ),

          _shift(
            'Tue, Aug 4',
            'DAY',
            '07:00 → 19:00',
          ),
        ],
      ),
    );
  }

  Widget _shift(
    String date,
    String type,
    String time,
  ) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: ListTile(
        leading: const Icon(
          Icons.event,
        ),
        title: Text(date),
        subtitle: Text(
          time.isEmpty
              ? type
              : '$type • $time',
        ),
      ),
    );
  }
}