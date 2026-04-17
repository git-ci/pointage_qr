import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/site.dart';
import 'screens/api_setup_screen.dart';
import 'screens/login_screen.dart';
import 'screens/terminal_screen.dart';
import 'services/api_service.dart';
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
/// 1. Pas d'URL API               → ApiSetupScreen
/// 2. Site configuré + même device → TerminalScreen (relancement direct)
/// 3. Sinon                        → LoginScreen
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
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');

    // Pas d'URL → configuration initiale
    if (apiUrl == null || apiUrl.isEmpty) {
      _go(const ApiSetupScreen());
      return;
    }

    // Récupérer le site sauvegardé localement
    final siteJson = await DeviceService.getTerminalSite();
    if (siteJson == null) {
      _go(const LoginScreen());
      return;
    }

    // Construire le site depuis le JSON local
    Site? site;
    try {
      site = Site.fromJson(Map<String, dynamic>.from(siteJson));
    } catch (_) {
      // JSON corrompu → reset et demander reconnexion
      await DeviceService.clearTerminalSite();
      _go(const LoginScreen());
      return;
    }

    // Récupérer l'ID de cet appareil
    final deviceId = await DeviceService.getDeviceId();

    try {
      // Vérifier côté serveur que cet appareil est autorisé
      final check = await ApiService.checkDevice(site.id, deviceId);
      if (check['authorized'] == true) {
        _go(TerminalScreen(site: site));
        return;
      }
      // Appareil non autorisé → retour au login
      _go(const LoginScreen());
    } catch (_) {
      // Serveur injoignable → lancer quand même le terminal en mode offline
      // La bannière de connectivité s'affichera dans TerminalScreen
      _go(TerminalScreen(site: site));
    }
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
      body: const Center(
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
