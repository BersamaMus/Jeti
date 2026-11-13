import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/apps_controller.dart';
import 'services/catalog.dart';
import 'theme.dart';

/// Jeti's catalog comes from the website, unless `--catalog=URL_OR_FILE` or
/// `JETI_CATALOG` says otherwise (e.g. the website's dist\apps.json, to try a
/// change before publishing it). On Android, which has neither, build with
/// `--dart-define=JETI_CATALOG=http://10.0.2.2:4321/apps.json` (the PC's
/// `npm run dev`, as an emulator sees it).
void main(List<String> args) {
  String? catalog;
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--catalog=')) catalog = args[i].substring('--catalog='.length);
    if (args[i] == '--catalog' && i + 1 < args.length) catalog = args[i + 1];
  }
  const defined = String.fromEnvironment('JETI_CATALOG');
  catalog ??= Platform.environment['JETI_CATALOG'] ?? (defined.isEmpty ? defaultCatalog : defined);

  runApp(JetiApp(controller: AppsController(catalogSource: catalog)));
}

class JetiApp extends StatelessWidget {
  const JetiApp({super.key, required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jeti',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(controller: controller),
    );
  }
}
