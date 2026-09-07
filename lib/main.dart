import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/connection_screen.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/community_screen.dart';
import 'package:heizungstrainer/screens/backup_screen.dart';

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
      create: (_) => ECLProvider(),
      child: const HeizungstrainerApp(),
    ),
  );
}

class HeizungstrainerApp extends StatelessWidget {
  const HeizungstrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

/// Main shell with bottom navigation bar containing 3 tabs.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    CommunityScreen(),
    BackupScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
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
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Vergleich',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud_done_rounded),
            label: 'Sicherungen',
          ),
        ],
      ),
    );
  }
}
