import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app/app.dart';
import 'core/utils/app_log.dart';
import 'core/utils/error_boundary.dart';
import 'data/database/hoza_database.dart';
import 'data/database/settings_store.dart';
import 'data/models/app_settings.dart';
import 'data/providers/settings_provider.dart';
import 'services/telemetry/crash_reporting.dart';

/// The most the first frame waits for the database and preferences.
///
/// Both are normally ready in a few tens of milliseconds, well inside the
/// native launch screen. A database that is slow — a locked file, a full
/// disk, a busy phone — must not hold a black screen: past this, the app
/// starts without it and the session runs with empty history and default
/// preferences, which the code below already handles.
const Duration _startupBudget = Duration(seconds: 2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything can fail: a build error must reach the console rather than
  // painting a red screen over the launch.
  ErrorBoundary.install();

  // Draw behind the status and navigation bars; the shell and sheets handle
  // their own safe-area insets.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Crash reporting wraps the app's own handlers, so it goes on after them
  // and everything below runs inside it.
  await CrashReporting.run(_start);
}

Future<void> _start() async {
  // Opening the database and reading preferences before the first frame keeps
  // the app from painting the default theme and then correcting itself. The
  // native launch screen covers this, and it is a few milliseconds of work —
  // bounded, so it can never become the thing the user is waiting on.
  Database? database;
  var settings = const AppSettings();
  try {
    database = await HozaDatabase.open().timeout(_startupBudget);
    settings = await SettingsStore(database).load().timeout(_startupBudget);
  } on TimeoutException {
    // Whichever step ran out of time, what was already opened is kept: a
    // database without preferences still holds the download history.
    AppLog.warn('Startup', 'storage not ready in time; starting without it');
  } catch (error, stack) {
    // A database that will not open costs history and preferences for this
    // session; it must not stop the app from starting.
    AppLog.error('Opening the database', error, stack);
  }

  runApp(
    ProviderScope(
      overrides: [
        if (database != null) databaseProvider.overrideWithValue(database),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const HozaApp(),
    ),
  );
}
