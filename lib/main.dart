import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/state/app_state.dart';
import 'features/discovery/server_discovery_page.dart';

void main() {
  runApp(const ComicReaderApp());
}

class ComicReaderApp extends StatelessWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Comic Reader',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: const ServerDiscoveryPage(),
      ),
    );
  }
}
