import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/connection_screen.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/screens/community_screen.dart';
import 'package:heizungstrainer/screens/backup_screen.dart';
import 'package:heizungstrainer/screens/log_screen.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/widgets/app_top_status_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF1E1E24),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    ChangeNotifierProvider(
      create: (_) => ECLProvider()..locationRationale = _showLocationRationale,
      child: const HeizungstrainerApp(),
    ),
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Explains the location permission before Android asks for it.
Future<bool> _showLocationRationale() async {
  final context = _navigatorKey.currentContext;
  if (context == null) return true;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.wifi_find_rounded),
      title: const Text('Regler im WLAN finden'),
      content: const Text(
        'Um deinen Heizungsregler automatisch im Heimnetz zu finden, muss die App '
        'die WLAN-Adresse deines Telefons lesen. Android erlaubt das nur mit der '
        'Standortberechtigung.\n\n'
        'Heizungstrainer nutzt deinen Standort nicht und speichert oder überträgt ihn '
        'nicht. Ohne die Berechtigung kannst du die IP-Adresse des Reglers über '
        '„IP manuell eingeben“ eintragen.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Nicht jetzt'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class HeizungstrainerApp extends StatelessWidget {
  const HeizungstrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Heizungstrainer',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: Consumer<ECLProvider>(
        builder: (context, provider, _) {
          if (provider.isConnected || provider.isOfflineMode) {
            return const MainShell();
          }
          return const ConnectionScreen();
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const background = Color(0xFF1E1E24);
    const surface = Color(0xFF1E1E24);
    const surfaceContainer = Color(0xFF2A2A32);
    const surfaceContainerHigh = Color(0xFF35353F);
    const onSurface = Color(0xFFECECF0);
    const onSurfaceVariant = Color(0xFF9E9EA8);
    const primary = Color(0xFFFFA726);
    const secondary = Color(0xFF7C4DFF);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        surfaceContainerLow: surfaceContainer,
        surfaceContainerHighest: surfaceContainerHigh,
        primary: primary,
        onPrimary: Colors.black,
        secondary: secondary,
        onSecondary: Colors.white,
        error: Color(0xFFEF5350),
        outlineVariant: Color(0xFF3A3A44),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF16161C),
        indicatorColor: primary.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            color: onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(color: onSurfaceVariant, size: 24);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: primary.withValues(alpha: 0.15),
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// Main shell with bottom navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  // Holiday-mode scheduler: applies a planned setback and restores normal
  // operation at the preheat time while the app runs. Also fires right after
  // (re)connecting, so steps missed while the controller was unreachable are
  // caught up.
  static const _holidayCheckInterval = Duration(minutes: 1);
  final HolidayService _holidayService = HolidayService();
  Timer? _holidayTimer;
  ECLProvider? _provider;
  bool _wasConnected = false;
  bool _holidayBusy = false;
  String? _lastHolidayError;

  @override
  void initState() {
    super.initState();
    _provider = context.read<ECLProvider>()..addListener(_onProviderChanged);
    _holidayTimer =
        Timer.periodic(_holidayCheckInterval, (_) => _runHolidaySchedule());
  }

  @override
  void dispose() {
    _holidayTimer?.cancel();
    _provider?.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    final connected = _provider?.isConnected ?? false;
    if (connected && !_wasConnected) _runHolidaySchedule();
    _wasConnected = connected;
  }

  Future<void> _runHolidaySchedule() async {
    final provider = _provider;
    if (_holidayBusy || provider == null || !provider.isConnected) return;
    _holidayBusy = true;
    try {
      final changed = await _holidayService.runDueActions(provider: provider);
      _lastHolidayError = null;
      if (changed != null && mounted) {
        final text = changed.isCompleted
            ? 'Abwesenheit "${changed.title}" beendet – Heizung zurück im Normalbetrieb.'
            : 'Abwesenheit "${changed.title}" gestartet – Heizung abgesenkt.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    } catch (e) {
      // Retried every minute; only surface a new error once.
      final message = e.toString();
      if (message != _lastHolidayError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abwesenheitsmodus: $message')),
        );
      }
      _lastHolidayError = message;
    } finally {
      _holidayBusy = false;
    }
  }

  static const _screens = <Widget>[
    HomeScreen(),
    HolidayScreen(),
    CommunityScreen(),
    BackupScreen(),
    LogScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppTopStatusBar(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _screens,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Mein Zuhause',
          ),
          NavigationDestination(
            icon: Icon(Icons.beach_access_outlined),
            selectedIcon: Icon(Icons.beach_access_rounded),
            label: 'Urlaub',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Vergleich',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud_done_rounded),
            label: 'Sicherungen',
          ),
          NavigationDestination(
            icon: _LogsIcon(selected: false),
            selectedIcon: _LogsIcon(selected: true),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}

/// Logs tab icon with the number of new alerts.
class _LogsIcon extends StatelessWidget {
  const _LogsIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final alerts = context.read<ECLProvider>().alerts;
    return ListenableBuilder(
      listenable: alerts,
      builder: (context, _) {
        final n = alerts.unacknowledgedCount;
        final icon = Icon(selected ? Icons.receipt_long_rounded : Icons.receipt_long_outlined);
        return n == 0 ? icon : Badge(label: Text('$n'), child: icon);
      },
    );
  }
}
