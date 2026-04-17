import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../models/site.dart';
import 'terminal_screen.dart';
import 'login_screen.dart';

class SuccessScreen extends StatefulWidget {
  final Site site;
  final bool isEdit;

  const SuccessScreen({super.key, required this.site, required this.isEdit});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  int _countdown = 10;
  Timer? _timer;
  String _status = 'Liaison de cet appareil au terminal…';
  bool _bound = false;

  @override
  void initState() {
    super.initState();
    _bindAndStart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bindAndStart() async {
    // 1. Récupérer les infos de l'appareil
    final deviceId = await DeviceService.getDeviceId();
    final deviceInfo = await DeviceService.getDeviceInfo();
    final label = '${deviceInfo['brand'] ?? ''} ${deviceInfo['model'] ?? ''} '
            '(${deviceInfo['os'] ?? ''})'
        .trim();

    // 2. Lier cet appareil au site sur le serveur
    try {
      await ApiService.bindDevice(widget.site.id, deviceId, label);
      // Sauvegarder le site localement (permet le relancement sans login)
      final siteMap = {
        'id': widget.site.id,
        'name': widget.site.name,
        'city': widget.site.city,
        'address': widget.site.address,
        'latitude': widget.site.latitude,
        'longitude': widget.site.longitude,
        'radius_meters': widget.site.radiusMeters,
        'active': widget.site.active,
        'gps_configured': widget.site.gpsConfigured,
        'terminal_url': widget.site.terminalUrl,
        'token': widget.site.token,
        'device_id': deviceId,
      };
      await DeviceService.saveTerminalSite(siteMap);
      setState(() {
        _bound = true;
        _status = 'Terminal lié à cet appareil ✅';
      });
    } catch (e) {
      // Si liaison échoue (réseau), sauvegarder quand même localement
      final siteMap = {
        'id': widget.site.id,
        'name': widget.site.name,
        'city': widget.site.city,
        'address': widget.site.address,
        'latitude': widget.site.latitude,
        'longitude': widget.site.longitude,
        'radius_meters': widget.site.radiusMeters,
        'active': widget.site.active,
        'gps_configured': widget.site.gpsConfigured,
        'terminal_url': widget.site.terminalUrl,
        'token': widget.site.token,
      };
      await DeviceService.saveTerminalSite(siteMap);
      setState(() {
        _bound = true;
        _status = 'Sauvegardé localement (liaison serveur à réessayer)';
      });
    }

    // 3. Déconnecter le DG
    await ApiService.logout();

    // 4. Démarrer le countdown
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
        _goToTerminal();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _goToTerminal() {
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => TerminalScreen(site: widget.site)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.isEdit ? 'mis à jour' : 'créé';

    return Scaffold(
      backgroundColor: const Color(0xFFf0f2f5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a2540),
        foregroundColor: Colors.white,
        title: const Text('Configuration terminée',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFFd3f9d8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle,
                      size: 48, color: Color(0xFF2b8a3e)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Terminal $action avec succès !',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2b8a3e),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Statut liaison device
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bound
                        ? const Color(0xFFd3f9d8)
                        : const Color(0xFFe7f5ff),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      _bound
                          ? const Icon(Icons.phonelink_lock,
                              color: Color(0xFF2b8a3e), size: 18)
                          : const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF1864ab))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12,
                          color: _bound
                              ? const Color(0xFF2b8a3e)
                              : const Color(0xFF1864ab),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 14, color: Colors.grey, height: 1.6),
                    children: [
                      const TextSpan(text: 'Le terminal '),
                      TextSpan(
                          text: widget.site.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1a2540))),
                      TextSpan(text: ' a été $action.\n'),
                      const TextSpan(
                          text:
                              'Cet appareil est maintenant le terminal officiel de ce site.'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Countdown
                if (_bound) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFfff3bf),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer,
                            size: 16, color: Color(0xFFe67700)),
                        const SizedBox(width: 8),
                        Text('Affichage du terminal dans $_countdown s…',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFe67700),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (10 - _countdown) / 10,
                      backgroundColor: const Color(0xFFdee2e6),
                      valueColor:
                          const AlwaysStoppedAnimation(Color(0xFF2b8a3e)),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _goToTerminal,
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Afficher le terminal maintenant',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2b8a3e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
