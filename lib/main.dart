import 'package:connectx/models/user.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'chat_screen.dart';
import 'login.dart';
import 'main_screen.dart';
import 'new_chat_screen.dart';
import 'group_chat_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (FirebaseAuth.instance.currentUser != null) {
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ConnectX',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      initialRoute: _user != null
          ? "/chat"
          : FirebaseAuth.instance.currentUser != null
              ? '/main'
              : '/login',
      routes: {
        '/login': (context) => const AuthPage(),
        '/main': (context) => const MainScreen(),
        '/chat': (context) => const ChatScreen(),
        '/group': (context) => const GroupChatScreen(),
        "/main/new": (context) => const NewChatScreen(),
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
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  const primary = Color(0xFF0AA5A8);
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    primary: primary,
    surface: isDark ? const Color(0xFF202C33) : Colors.white,
    background: isDark ? const Color(0xFF111B21) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFFFFFFF),
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? const Color(0xFF1F2C34) : const Color(0xFF087F83),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 6,
    ),
    dividerColor: isDark ? const Color(0xFF222D34) : const Color(0xFFE9EDEF),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF202C33) : const Color(0xFFF0F2F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 1.4),
      ),
    ),
  );
}
