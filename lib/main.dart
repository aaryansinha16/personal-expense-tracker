import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'services/background_sync.dart';
import 'services/notifications.dart';
import 'services/share_receiver.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  ));
  runApp(const ExpenseApp());
}

class ExpenseApp extends StatefulWidget {
  const ExpenseApp({super.key});

  @override
  State<ExpenseApp> createState() => _ExpenseAppState();
}

class _ExpenseAppState extends State<ExpenseApp> {
  late final ShareReceiver _share;

  @override
  void initState() {
    super.initState();
    _share = ShareReceiver(appNavigatorKey);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _share.start();
      await NotificationsService.instance.init();
      await BackgroundSync.instance.initialize();
      // If the user had auto-resume-sync enabled, re-apply it so the
      // lifecycle observer starts firing.
      final prefs = await SharedPreferences.getInstance();
      final on = prefs.getBool('pref_bg_gmail_sync') ?? false;
      await BackgroundSync.instance.setEnabled(on);
    });
  }

  @override
  void dispose() {
    _share.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final s = AppState()..init();
        BackgroundSync.instance.bindAppState(s);
        return s;
      },
      child: MaterialApp(
        title: 'Expense Tracker',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
