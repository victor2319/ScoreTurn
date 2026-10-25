import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const AutoScoreApp());
}

class AutoScoreApp extends StatelessWidget {
  const AutoScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF142439);
    const teal = Color(0xFF007E80);
    return MaterialApp(
      title: 'AutoScore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: teal, primary: teal),
        scaffoldBackgroundColor: const Color(0xFFF5F5F1),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy, foregroundColor: Colors.white,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(color: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      home: const LibraryScreen(),
    );
  }
}
