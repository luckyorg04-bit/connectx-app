import 'dart:ui' as ui;
import 'package:connectx/models/user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'chat_screen.dart';
import 'connect_qr_screen.dart';
import 'login.dart';
import 'main_screen.dart';
import 'new_chat_screen.dart';
import 'group_chat_screen.dart';
import 'group_call_screen.dart';
import 'services/notification_service.dart';
import 'call_screen.dart';
import 'app_navigator.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import 'services/app_preferences.dart';

bool _globalErrorDialogVisible = false;

void _showGlobalErrorDialog() {
  if (_globalErrorDialogVisible) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted || _globalErrorDialogVisible) return;
    _globalErrorDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
          title: const Text('Something went wrong'),
          content: const Text('ConnectX hit an unexpected problem. Your account data has not been intentionally changed. Please try again.'),
          actions: [FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          )],
        ),
      );
    } finally {
      _globalErrorDialogVisible = false;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = (details) {
    debugPrint('ConnectX framework error: ${details.exceptionAsString()}');
    _showGlobalErrorDialog();
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('ConnectX uncaught error: $error');
    _showGlobalErrorDialog();
    return true;
  };
  ErrorWidget.builder = (details) => const Material(
    color: Color(0xFF0B141B),
    child: Center(child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('Something went wrong. Please return and try again.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 15)),
    )),
  );
  if (FirebaseAuth.instance.currentUser != null) {
    await AppPreferences.load();
    await NotificationService.initialize();
  }
  runApp(const MyApp(user: null));
}

const title = "ConnectX";
User1? _user;
String currentRoute = "";

class MyApp extends StatelessWidget {
  final User1? user;

  const MyApp({Key? key, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    _user = user;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppPreferences.themeMode,
      builder: (context, selectedThemeMode, _) => ValueListenableBuilder<Locale>(
        valueListenable: AppPreferences.locale,
        builder: (context, selectedLocale, _) => MaterialApp(
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final pending = pendingCallArguments;
          if (pending != null && FirebaseAuth.instance.currentUser != null) {
            pendingCallArguments = null;
            openIncomingCall(pending);
          }
          final pendingChatUid = pendingDirectChatUid;
          if (pendingChatUid != null && FirebaseAuth.instance.currentUser != null) {
            pendingDirectChatUid = null;
            openDirectChat(pendingChatUid);
          }
        });
        return child ?? const SizedBox.shrink();
      },
      debugShowCheckedModeBanner: false,
      title: 'ConnectX',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: selectedThemeMode,
      locale: selectedLocale,
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      initialRoute: _user != null
          ? "/chat"
          : FirebaseAuth.instance.currentUser != null
              ? '/main'
              : '/login',
      routes: {
        '/login': (context) => const AuthPage(),
        '/main': (context) => const MainScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/edit-profile': (context) => const EditProfileScreen(),
        '/chat': (context) => const ChatScreen(),
        '/group': (context) => const GroupChatScreen(),
        '/group-call': (context) => const GroupCallScreen(),
        '/call': (context) => const CallScreen(),
        "/main/new": (context) => const NewChatScreen(),
        "/my-qr": (context) => const ConnectQrScreen(),
        "/scan-qr": (context) => const ConnectQrScreen(scanMode: true),
      },
      onGenerateInitialRoutes: (String initialRouteName) {
        if (initialRouteName == "/chat") {
          return [
            MaterialPageRoute(
              settings: RouteSettings(name: "/chat", arguments: _user),
              builder: (BuildContext context) => const ChatScreen(),
            )
          ];
        }
        return [
          MaterialPageRoute(
            settings: RouteSettings(name: initialRouteName),
            builder: (BuildContext context) => initialRouteName == "/main"
                ? const MainScreen()
                : const AuthPage(),
          )
        ];
      },
        ),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  const lightGreen = Color(0xFF008069);
  const darkGreen = Color(0xFF59DCB5);
  final primary = isDark ? darkGreen : lightGreen;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    primary: primary,
    secondary: isDark ? const Color(0xFF8BD5BF) : const Color(0xFF25D366),
    surface: isDark ? const Color(0xFF141D24) : Colors.white,
    background: isDark ? const Color(0xFF0B141B) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: isDark ? const Color(0xFF0B141B) : Colors.white,
    appBarTheme: AppBarTheme(
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: Colors.white,
      ),
      backgroundColor: isDark ? const Color(0xFF141D24) : lightGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: isDark ? const Color(0xFF141D24) : Colors.white,
      indicatorColor: isDark ? const Color(0xFF005B4A) : const Color(0xFFE7FCE3),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontFamily: 'Roboto',
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: isDark ? const Color(0xFFDAE4ED) : const Color(0xFF111B21),
      )),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: isDark ? const Color(0xFF2D363D) : const Color(0xFFE9EDEF),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? const Color(0xFF141D24) : const Color(0xFFF7F8F8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF222B32) : const Color(0xFFF0F2F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.4),
      ),
    ),
  );
}
