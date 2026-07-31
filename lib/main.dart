import 'package:flutter/material.dart';

import 'src/game.dart';
import 'src/screens.dart';

void main() => runApp(const OneNightMatchApp());

class OneNightMatchApp extends StatelessWidget {
  const OneNightMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ONE NIGHT MATCH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffff3d32),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0c0d12),
        cardTheme: const CardThemeData(color: Color(0xff191b24)),
        useMaterial3: true,
      ),
      home: TitleScreen(catalog: GameCatalog.standard()),
    );
  }
}
