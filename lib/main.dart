import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/discovery/server_discovery_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
        theme: buildAppTheme(),
        home: const ServerDiscoveryPage(),
      ),
    );
  }
}
