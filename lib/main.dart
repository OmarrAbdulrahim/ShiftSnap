import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
