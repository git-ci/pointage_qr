import 'package:flutter/material.dart';
import 'models/site.dart';
import 'screens/login_screen.dart';
import 'screens/terminal_screen.dart';
import 'services/device_service.dart';
import 'widgets/app_logo.dart';

void main() {
  runApp(const TerminalSetupApp());
}

class TerminalSetupApp extends StatelessWidget {
  const TerminalSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PointageQr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1a2540),
          primary: const Color(0xFF1a2540),
        ),
        fontFamily: 'SF Pro Display',
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      home: const SplashRouter(),
    );
  }
}

/// Logique de routage au démarrage :
/// 1. Site configuré + même device → TerminalScreen (relancement direct)
/// 2. Sinon                        → LoginScreen
class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    // Site sauvegardé localement → lancer le terminal directement
    final siteJson = await DeviceService.getTerminalSite();
    if (siteJson == null) {
      _go(const LoginScreen());
      return;
    }

    Site site;
    try {
      site = Site.fromJson(Map<String, dynamic>.from(siteJson));
    } catch (_) {
      // JSON corrompu → reset
      await DeviceService.clearTerminalSite();
      _go(const LoginScreen());
      return;
    }

    _go(TerminalScreen(site: site));
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1a2540),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 96, showName: true),
            SizedBox(height: 36),
            CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}
