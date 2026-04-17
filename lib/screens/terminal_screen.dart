import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../models/site.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TerminalScreen — Page principale du terminal de pointage QR
// ─────────────────────────────────────────────────────────────────────────────
class TerminalScreen extends StatefulWidget {
  final Site site;
  const TerminalScreen({super.key, required this.site});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  // ── Vérification appareil ─────────────────────────────────────────────────
  bool _deviceChecked = false;
  bool _deviceAuthorized = false;
  String _deviceBlockMsg = '';

  // ── État QR ───────────────────────────────────────────────────────────────
  String? _scanUrl;
  bool _loadingQr = true;
  String? _qrError;
  int _countdown = 90;
  Timer? _qrTimer;

  // ── Connectivité ──────────────────────────────────────────────────────────
  bool _hasInternet = true;
  bool _hasApi = true;
  Timer? _connectTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  // ── Horloge ───────────────────────────────────────────────────────────────
  String _clockText = '';
  String _dateText = '';
  Timer? _clockTimer;

  // ── Blocage horaire ───────────────────────────────────────────────────────
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    _checkDeviceAuthorization();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qrTimer?.cancel();
    _clockTimer?.cancel();
    _connectTimer?.cancel();
    _connectSub?.cancel();
    super.dispose();
  }

  // ── Horloge en temps réel ─────────────────────────────────────────────────
  void _startClock() {
    _updateClock();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  // Heures de réactivation du QR (5h30)
  static const int _resetHour = 5;
  static const int _resetMin = 30;

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final weekdays = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    final months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre'
    ];
    final day = weekdays[now.weekday - 1];
    final date = '$day ${now.day} ${months[now.month - 1]} ${now.year}';

    // Deadline depuis le site
    final deadline = widget.site.checkinDeadline;
    final dParts = deadline.split(':');
    final dlHour = int.tryParse(dParts[0]) ?? 10;
    final dlMin = int.tryParse(dParts.length > 1 ? dParts[1] : '0') ?? 0;
    final nowMins = now.hour * 60 + now.minute;
    final dlMins = dlHour * 60 + dlMin;
    final rstMins = _resetHour * 60 + _resetMin; // 5h30 = 330 min

    // Fenêtre de blocage : [dlMins..23h59] + [0h00..rstMins[
    // = nowMins >= dlMins  OU  nowMins < rstMins
    final newBlocked = (nowMins >= dlMins) || (nowMins < rstMins);
    final wasBlocked = _isBlocked;

    if (mounted) {
      setState(() {
        _clockText = '$h:$m';
        _dateText = date;
        _isBlocked = newBlocked;
      });
      if (!wasBlocked && newBlocked) {
        _qrTimer?.cancel(); // Vient de se bloquer
      } else if (wasBlocked && !newBlocked) {
        _fetchQr(); // Vient de se débloquer → relancer le QR
      }
    }
  }

  // ── Vérification que cet appareil est autorisé ────────────────────────────
  Future<void> _checkDeviceAuthorization() async {
    final deviceId = await DeviceService.getDeviceId();
    try {
      final result = await ApiService.checkDevice(widget.site.id, deviceId);
      final authorized = result['authorized'] as bool? ?? false;

      if (authorized) {
        // Si le site n'est pas encore lié, le lier maintenant
        if (result['reason'] == 'not_bound') {
          final info = await DeviceService.getDeviceInfo();
          final label =
              '${info['brand'] ?? ''} ${info['model'] ?? ''} (${info['os'] ?? ''})'
                  .trim();
          await ApiService.bindDevice(widget.site.id, deviceId, label);
          // Sauvegarder localement
          await DeviceService.saveTerminalSite({
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
          });
        }
        setState(() {
          _deviceChecked = true;
          _deviceAuthorized = true;
        });
        _startConnectivityWatch();
        _fetchQr();
      } else {
        setState(() {
          _deviceChecked = true;
          _deviceAuthorized = false;
          _deviceBlockMsg = result['message'] as String? ??
              'Cet appareil n\'est pas autorisé à afficher ce terminal.';
        });
      }
    } catch (_) {
      // Serveur injoignable → autoriser en mode offline (l'appareil a déjà le site sauvegardé)
      setState(() {
        _deviceChecked = true;
        _deviceAuthorized = true;
      });
      _startConnectivityWatch();
      _fetchQr();
    }
  }

  // ── Surveillance connectivité ─────────────────────────────────────────────
  void _startConnectivityWatch() {
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online && _hasInternet) {
        setState(() {
          _hasInternet = false;
          _hasApi = false;
        });
        _qrTimer?.cancel();
      } else if (online && !_hasInternet) {
        setState(() {
          _hasInternet = true;
        });
        _fetchQr(); // Re-tenter dès retour connexion
      }
    });

    // Vérification périodique de l'API (toutes les 30s)
    _connectTimer =
        Timer.periodic(const Duration(seconds: 90), (_) => _checkApi());
  }

  Future<void> _checkApi() async {
    final apiUrl = AppConfig.apiBaseUrl;
    try {
      final res = await http.get(Uri.parse('$apiUrl/api/v1/setup/status'),
          headers: {
            'Accept': 'application/json'
          }).timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _hasApi = res.statusCode < 500);
    } catch (_) {
      if (mounted) setState(() => _hasApi = false);
    }
  }

  // ── Génération du QR ──────────────────────────────────────────────────────
  Future<void> _fetchQr() async {
    _qrTimer?.cancel();
    if (mounted)
      setState(() {
        _loadingQr = true;
        _qrError = null;
      });

    // Vérifier connectivité basique
    final results = await Connectivity().checkConnectivity();
    final online = results.any((r) => r != ConnectivityResult.none);
    if (!online) {
      if (mounted)
        setState(() {
          _loadingQr = false;
          _hasInternet = false;
          _qrError =
              'Pas de connexion Internet.\nVérifiez le Wi-Fi ou les données mobiles.';
        });
      return;
    }

    final apiUrl = AppConfig.apiBaseUrl;

    try {
      final res = await http.get(
        Uri.parse('$apiUrl/api/v1/qr/generate?site_id=${widget.site.id}'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('Erreur serveur ${res.statusCode}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final payload = data['payload'] as String;
      final signature = data['signature'] as String;

      // URL que le téléphone ouvrira après avoir scanné
      final scanUrl = '$apiUrl/scan'
          '?payload=${Uri.encodeComponent(payload)}'
          '&sig=${Uri.encodeComponent(signature)}';

      if (mounted)
        setState(() {
          _scanUrl = scanUrl;
          _loadingQr = false;
          _hasInternet = true;
          _hasApi = true;
          _countdown = 90;
        });

      _startCountdown();
    } catch (e) {
      if (mounted)
        setState(() {
          _loadingQr = false;
          _hasApi = false;
          _qrError =
              'Impossible de contacter le serveur.\n${e.toString().replaceAll('Exception: ', '')}';
        });
      // Retry dans 10s
      _qrTimer = Timer(const Duration(seconds: 10), _fetchQr);
    }
  }

  void _startCountdown() {
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _fetchQr();
      }
    });
  }

  // ── Réinitialisation — demande auth DG ────────────────────────────────────
  void _showResetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetDialog(
        onConfirmed: () async {
          await ApiService.clearToken();
          await DeviceService.clearTerminalSite();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Chargement initial (vérification appareil) ────────────────────────
    if (!_deviceChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a2540),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🖥️', style: TextStyle(fontSize: 48)),
              SizedBox(height: 20),
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Vérification de l\'appareil…',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // ── Appareil non autorisé ─────────────────────────────────────────────
    if (!_deviceAuthorized) {
      return Scaffold(
        backgroundColor: const Color(0xFF1a2540),
        body: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phonelink_erase,
                    size: 56, color: Color(0xFFc92a2a)),
                const SizedBox(height: 16),
                const Text(
                  'Appareil non autorisé',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFc92a2a)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _deviceBlockMsg,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.grey, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pour utiliser ce terminal sur cet appareil, demandez au DG de délier '
                  'l\'appareil actuel dans les paramètres du site.',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Se connecter en tant que DG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a2540),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a2540),
      body: SafeArea(
        child: Column(
          children: [
            // ── Bannière de connectivité ──────────────────────────────────
            if (!_hasInternet || !_hasApi)
              _ConnectivityBanner(
                hasInternet: _hasInternet,
                hasApi: _hasApi,
                onRetry: _fetchQr,
              ),

            // ── Contenu principal ─────────────────────────────────────────
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo PointageQr
                      const AppLogo(size: 100, showName: false),
                      const SizedBox(height: 12),

                      // Nom du site
                      Text(
                        widget.site.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Ville
                      if (widget.site.city != null &&
                          widget.site.city!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '📍 ${widget.site.city}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Horloge
                      Text(
                        _clockText,
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _dateText,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white54),
                      ),

                      const SizedBox(height: 20),

                      // ── Cadre QR ─────────────────────────────────────────
                      _QrFrame(
                        loading: _loadingQr,
                        error: _qrError,
                        scanUrl: _scanUrl,
                        countdown: _countdown,
                        onRetry: _fetchQr,
                        isBlocked: _isBlocked,
                        checkinDeadline: widget.site.checkinDeadline,
                      ),

                      const SizedBox(height: 16),

                      // Instruction
                      if (_scanUrl != null && !_loadingQr) ...[
                        const Text(
                          'Scannez ce QR code avec votre téléphone\npour enregistrer votre présence.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Le code se renouvelle automatiquement toutes les 90 secondes.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.4),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── Boutons ────────────────────────────────────────────
                      _ActionButtons(
                        onRefresh: _fetchQr,
                        onReset: _showResetDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget : Cadre QR avec état loading / error / affiché
// ─────────────────────────────────────────────────────────────────────────────
class _QrFrame extends StatelessWidget {
  final bool loading;
  final String? error;
  final String? scanUrl;
  final int countdown;
  final VoidCallback onRetry;
  final bool isBlocked;
  final String checkinDeadline;

  const _QrFrame({
    required this.loading,
    required this.error,
    required this.scanUrl,
    required this.countdown,
    required this.onRetry,
    this.isBlocked = false,
    this.checkinDeadline = '10:00',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // QR ou état
          SizedBox(
            width: 260,
            height: 260,
            child: _buildQrContent(),
          ),

          // Barre de countdown (seulement si QR affiché)
          if (scanUrl != null && !loading) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Expire dans',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: countdown / 90,
                      backgroundColor: const Color(0xFFf1f3f5),
                      valueColor: AlwaysStoppedAnimation(
                        countdown <= 15
                            ? const Color(0xFFf87171)
                            : const Color(0xFF4ade80),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${countdown}s',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: countdown <= 15
                          ? const Color(0xFFc92a2a)
                          : const Color(0xFF2b8a3e),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQrContent() {
    // ── État BLOQUÉ ──────────────────────────────────────────────────────────
    if (isBlocked) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⛔', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Pointage fermé',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFFc92a2a),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFffe3e3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '🕐 Heure limite : $checkinDeadline',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFc92a2a),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'L\'heure de pointage est dépassée.\nLe QR sera disponible à nouveau demain.',
            style:
                TextStyle(fontSize: 11, color: Color(0xFF868e96), height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFe7f5ff),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '🔄 Réactivation à 05:30',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1971c2),
              ),
            ),
          ),
        ],
      );
    }

    // ── Chargement ───────────────────────────────────────────────────────────
    if (loading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF1a2540), strokeWidth: 3),
          SizedBox(height: 16),
          Text('Génération du QR…',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      );
    }

    if (error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: Color(0xFFc92a2a)),
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: Color(0xFFc92a2a)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Réessayer', style: TextStyle(fontSize: 13)),
          ),
        ],
      );
    }

    if (scanUrl != null) {
      return QrImageView(
        data: scanUrl!,
        version: QrVersions.auto,
        size: 260,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF1a2540),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF1a2540),
        ),
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );
    }

    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget : Bannière de connectivité
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectivityBanner extends StatelessWidget {
  final bool hasInternet;
  final bool hasApi;
  final VoidCallback onRetry;

  const _ConnectivityBanner({
    required this.hasInternet,
    required this.hasApi,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isNetError = !hasInternet;
    final msg = isNetError
        ? '📶 Connexion Internet perdue. Vérifiez le Wi-Fi ou les données mobiles.'
        : '🔌 Impossible de contacter le serveur API. Le réseau est disponible mais le serveur ne répond pas.';

    return Material(
      color: isNetError ? const Color(0xFFc92a2a) : const Color(0xFFe67700),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isNetError ? Icons.signal_wifi_off : Icons.cloud_off,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Réessayer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget : Boutons Actualiser / Réinitialiser
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButtons extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onReset;

  const _ActionButtons({required this.onRefresh, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Actualiser
        ElevatedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualiser',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.15),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.3)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        // Réinitialiser
        ElevatedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.settings_backup_restore, size: 18),
          label: const Text('Réinitialiser',
              style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.08),
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog : Réinitialisation — demande connexion DG + confirmation
// ─────────────────────────────────────────────────────────────────────────────
class _ResetDialog extends StatefulWidget {
  final VoidCallback onConfirmed;
  const _ResetDialog({required this.onConfirmed});

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  // Étape 1 : auth DG | Étape 2 : confirmation
  int _step = 1;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Veuillez remplir tous les champs.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      final user = data['user'] as Map<String, dynamic>?;
      if (user == null || user['role'] != 'dg') {
        throw ApiException(
            'Accès refusé. Seul le compte DG peut réinitialiser.');
      }
      // Sauvegarder le token temporairement pour les appels suivants
      await ApiService.saveToken(data['token'] as String);
      setState(() {
        _loading = false;
        _step = 2;
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _step == 1 ? Icons.lock_outlined : Icons.warning_amber_rounded,
            color:
                _step == 1 ? const Color(0xFF1a2540) : const Color(0xFFe67700),
          ),
          const SizedBox(width: 10),
          Text(
            _step == 1
                ? 'Authentification requise'
                : 'Confirmer la réinitialisation',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: _step == 1 ? _buildAuthStep() : _buildConfirmStep(),
      actions: _step == 1 ? _authActions() : _confirmActions(),
    );
  }

  // ── Étape 1 : connexion DG ────────────────────────────────────────────────
  Widget _buildAuthStep() {
    return SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'La réinitialisation efface la configuration de ce terminal. '
            'Connectez-vous avec un compte DG pour continuer.',
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFffe3e3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFc92a2a))),
            ),
            const SizedBox(height: 12),
          ],

          // Email
          const Text('EMAIL DG',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: _inputDeco(hint: 'email@exemple.com'),
          ),
          const SizedBox(height: 12),

          // Mot de passe
          const Text('MOT DE PASSE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.grey)),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            onSubmitted: (_) => _authenticate(),
            decoration: _inputDeco(
              hint: '••••••••',
              suffix: IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _authActions() {
    return [
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      ElevatedButton(
        onPressed: _loading ? null : _authenticate,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1a2540),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('Vérifier'),
      ),
    ];
  }

  // ── Étape 2 : confirmation ─────────────────────────────────────────────────
  Widget _buildConfirmStep() {
    return SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFfff3bf),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFffd43b)),
            ),
            child: const Text(
              '⚠️ Cette action va effacer la configuration de ce terminal '
              '(URL du serveur, compte connecté).\n\n'
              'L\'application reviendra à l\'écran de configuration initiale.',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: Color(0xFF7a5000)),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Êtes-vous sûr de vouloir continuer ?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  List<Widget> _confirmActions() {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          widget.onConfirmed();
        },
        icon: const Icon(Icons.delete_forever, size: 18),
        label: const Text('Réinitialiser'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFc92a2a),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ];
  }

  InputDecoration _inputDeco({String? hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFdee2e6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFdee2e6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFF1a2540), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
    );
  }
}
