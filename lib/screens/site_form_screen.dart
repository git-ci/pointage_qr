import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../models/site.dart';

class SiteFormScreen extends StatefulWidget {
  final Site? site;
  const SiteFormScreen({super.key, this.site});

  @override
  State<SiteFormScreen> createState() => _SiteFormScreenState();
}

class _SiteFormScreenState extends State<SiteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '50');
  final _deadlineCtrl = TextEditingController(text: '10:00');
  final _checkoutStartCtrl = TextEditingController(text: '17:00');

  bool _loading = false;
  bool _gpsExpanded = false;
  String? _error;
  String? _gpsStatus;
  Color _gpsStatusColor = Colors.grey;

  bool get _isEdit => widget.site != null;
  bool get _gpsSet =>
      _latCtrl.text.trim().isNotEmpty && _lngCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final s = widget.site!;
      _nameCtrl.text = s.name;
      _cityCtrl.text = s.city ?? '';
      _addressCtrl.text = s.address ?? '';
      _latCtrl.text = s.latitude != null ? s.latitude!.toString() : '';
      _lngCtrl.text = s.longitude != null ? s.longitude!.toString() : '';
      _radiusCtrl.text = s.radiusMeters.toString();
      _deadlineCtrl.text = s.checkinDeadline;
      _checkoutStartCtrl.text = s.checkoutStart;
    }
    _latCtrl.addListener(_onLatChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _deadlineCtrl.dispose();
    _checkoutStartCtrl.dispose();
    super.dispose();
  }

  // Auto-split quand l'utilisateur colle "lat, lng" dans le champ latitude
  void _onLatChanged() {
    final val = _latCtrl.text.trim();
    if (val.contains(',')) {
      final parts = val.split(',');
      if (parts.length >= 2) {
        final lat = parts[0].trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
        final lng = parts[1].trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
        if (lat.isNotEmpty &&
            lng.isNotEmpty &&
            double.tryParse(lat) != null &&
            double.tryParse(lng) != null) {
          _latCtrl.removeListener(_onLatChanged);
          setState(() {
            _latCtrl.text = lat;
            _lngCtrl.text = lng;
            _latCtrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _latCtrl.text.length),
            );
          });
          _latCtrl.addListener(_onLatChanged);
        }
      }
    }
  }

  // ── GPS : option A — GPS natif ─────────────────────────────────────────────

  Future<void> _tryBrowserGps() async {
    setState(() {
      _gpsStatus = 'Demande de permission…';
      _gpsStatusColor = Colors.grey;
    });

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final req = await Geolocator.requestPermission();
      if (req == LocationPermission.denied ||
          req == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatus =
              '❌ Permission GPS refusée. Activez-la dans les réglages.';
          _gpsStatusColor = const Color(0xFFc92a2a);
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _gpsStatus =
            '❌ GPS bloqué. Activez la localisation dans Réglages > Application.';
        _gpsStatusColor = const Color(0xFFc92a2a);
      });
      return;
    }

    setState(() {
      _gpsStatus = 'Localisation en cours…';
    });

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(7);
        _lngCtrl.text = pos.longitude.toStringAsFixed(7);
        _gpsStatus =
            '✅ Position obtenue (précision : ~${pos.accuracy.round()} m)';
        _gpsStatusColor = const Color(0xFF2b8a3e);
      });
    } catch (e) {
      setState(() {
        _gpsStatus =
            '❌ Délai GPS dépassé. Utilisez l\'option IP ou Google Maps.';
        _gpsStatusColor = const Color(0xFFc92a2a);
      });
    }
  }

  // ── GPS : option B — Par IP ────────────────────────────────────────────────

  Future<void> _tryIpGeo() async {
    setState(() {
      _gpsStatus = 'Interrogation du service…';
      _gpsStatusColor = Colors.grey;
    });
    try {
      final res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['latitude'] == null || data['longitude'] == null) {
        throw Exception('Réponse invalide');
      }
      final lat = (data['latitude'] as num).toDouble();
      final lng = (data['longitude'] as num).toDouble();
      final city = data['city'] as String? ?? '';
      setState(() {
        _latCtrl.text = lat.toStringAsFixed(7);
        _lngCtrl.text = lng.toStringAsFixed(7);
        _gpsStatus =
            '⚠️ Approximatif ~1–5 km${city.isNotEmpty ? " — $city" : ""}. Affinez si besoin.';
        _gpsStatusColor = const Color(0xFFe67700);
      });
    } catch (e) {
      setState(() {
        _gpsStatus = '❌ Service IP indisponible. Utilisez Google Maps.';
        _gpsStatusColor = const Color(0xFFc92a2a);
      });
    }
  }

  // ── GPS : option C — Google Maps ───────────────────────────────────────────

  Future<void> _openGoogleMaps() async {
    final uri = Uri.parse('https://maps.google.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Sauvegarde ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    var latRaw = _latCtrl.text.trim();
    var lngRaw = _lngCtrl.text.trim();

    // Dernier essai d'auto-split (cas où coller n'a pas déclenché le listener)
    if (latRaw.contains(',')) {
      final parts = latRaw.split(',');
      latRaw = parts[0].trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
      if (lngRaw.isEmpty && parts.length >= 2) {
        lngRaw = parts[1].trim().replaceAll(RegExp(r'[^0-9.\-]'), '');
      }
    }

    final lat = latRaw.isNotEmpty ? double.tryParse(latRaw) : null;
    final lng = lngRaw.isNotEmpty ? double.tryParse(lngRaw) : null;
    final radius = int.tryParse(_radiusCtrl.text.trim()) ?? 50;
    final deadline =
        _deadlineCtrl.text.trim().isEmpty ? '10:00' : _deadlineCtrl.text.trim();
    final checkoutStart = _checkoutStartCtrl.text.trim().isEmpty
        ? '17:00'
        : _checkoutStartCtrl.text.trim();

    if ((lat != null && lng == null) || (lng != null && lat == null)) {
      setState(() {
        _loading = false;
        _error = 'Saisissez à la fois la latitude ET la longitude.';
      });
      return;
    }

    final payload = {
      'name': _nameCtrl.text.trim(),
      'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      'address':
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      'active': true,
      'latitude': lat,
      'longitude': lng,
      'radius_meters': radius,
      'checkin_deadline': deadline,
      'checkout_start': checkoutStart,
    };

    try {
      final data = _isEdit
          ? await ApiService.updateSite(widget.site!.id, payload)
          : await ApiService.createSite(payload);

      if (!mounted) return;
      Navigator.of(context).pop(data);
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf0f2f5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a2540),
        foregroundColor: Colors.white,
        title: Text(
          _isEdit ? '✏️ Modifier — ${widget.site!.name}' : '＋ Nouveau terminal',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) ...[
              _errorBox(_error!),
              const SizedBox(height: 12),
            ],

            // ── Informations générales ──────────────────────────────────────
            _section('INFORMATIONS DU SITE'),
            const SizedBox(height: 10),
            _card([
              _field(
                controller: _nameCtrl,
                label: 'Nom du site *',
                hint: 'Ex : Siège social, Entrepôt Nord…',
                icon: Icons.business,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Champ obligatoire.'
                    : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _cityCtrl,
                label: 'Ville',
                hint: 'Ex : Abidjan',
                icon: Icons.location_city,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _addressCtrl,
                label: 'Adresse complète',
                hint: 'Ex : 12 Avenue de la République, Plateau',
                icon: Icons.place_outlined,
              ),
            ]),

            const SizedBox(height: 20),

            // ── GPS ─────────────────────────────────────────────────────────
            _section('COORDONNÉES GPS'),
            const SizedBox(height: 10),
            _card([
              // Badge état GPS
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _gpsSet
                          ? const Color(0xFFd3f9d8)
                          : const Color(0xFFfff3bf),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _gpsSet
                          ? '📍 Coordonnées configurées'
                          : '⚠️ Non configurées — GPS désactivé',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _gpsSet
                            ? const Color(0xFF2b8a3e)
                            : const Color(0xFFe67700),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Latitude
              _label('Latitude'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _inputDeco(
                  hint: 'Ex : 5.345317  — ou coller : 5.345317, -4.024429',
                  icon: const Icon(Icons.my_location,
                      size: 18, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),

              // Longitude
              _label('Longitude'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _inputDeco(
                  hint: 'Ex : -4.024429',
                  icon: const Icon(Icons.my_location,
                      size: 18, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 14),

              // Rayon
              _label('Rayon autorisé (mètres) — recommandé 30–100 m'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _radiusCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDeco(
                  hint: '50',
                  icon: const Icon(Icons.radar, size: 18, color: Colors.grey),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  if (n == null || n < 10 || n > 500)
                    return 'Entre 10 et 500 mètres.';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Heure limite de pointage
              _label('⏰ Heure limite de pointage — défaut 10:00'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _deadlineCtrl,
                keyboardType: TextInputType.datetime,
                decoration: _inputDeco(
                  hint: '10:00',
                  icon: const Icon(Icons.access_time,
                      size: 18, color: Colors.grey),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final parts = v.split(':');
                  if (parts.length != 2)
                    return 'Format HH:MM requis (ex: 10:00).';
                  final h = int.tryParse(parts[0]);
                  final m = int.tryParse(parts[1]);
                  if (h == null || m == null || h > 23 || m > 59)
                    return 'Heure invalide.';
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Après cette heure, le pointage QR est refusé pour ce terminal.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),

              const SizedBox(height: 14),

              // Heure d'ouverture du pointage départ
              _label('🚪 Heure de départ — défaut 17:00'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _checkoutStartCtrl,
                keyboardType: TextInputType.datetime,
                decoration: _inputDeco(
                  hint: '17:00',
                  icon: const Icon(Icons.exit_to_app,
                      size: 18, color: Colors.grey),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final parts = v.split(':');
                  if (parts.length != 2) {
                    return 'Format HH:MM requis (ex: 17:00).';
                  }
                  final h = int.tryParse(parts[0]);
                  final m = int.tryParse(parts[1]);
                  if (h == null || m == null || h > 23 || m > 59) {
                    return 'Heure invalide.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'À partir de cette heure, le QR de départ devient disponible.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),

              const SizedBox(height: 14),

              // Bouton toggle aide GPS
              TextButton.icon(
                onPressed: () => setState(() => _gpsExpanded = !_gpsExpanded),
                icon: Icon(
                  _gpsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _gpsExpanded
                      ? 'Masquer l\'aide GPS'
                      : '📍 Obtenir les coordonnées automatiquement',
                  style: const TextStyle(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1864ab),
                  padding: EdgeInsets.zero,
                ),
              ),

              // Panel aide GPS (dépliable)
              if (_gpsExpanded) ...[
                const Divider(),
                const SizedBox(height: 8),

                // Statut GPS
                if (_gpsStatus != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _gpsStatusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _gpsStatusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      _gpsStatus!,
                      style: TextStyle(fontSize: 12, color: _gpsStatusColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Option A
                _gpsOption(
                  emoji: '📱',
                  title: 'Option A — GPS du téléphone',
                  subtitle:
                      'Précis, fonctionne sur smartphone avec GPS activé.',
                  onTap: _tryBrowserGps,
                  label: 'Utiliser le GPS',
                ),
                const SizedBox(height: 8),

                // Option B
                _gpsOption(
                  emoji: '🌐',
                  title: 'Option B — Position par IP (~1–5 km)',
                  subtitle: 'Approximatif. Fonctionne sur tous les appareils.',
                  onTap: _tryIpGeo,
                  label: 'Position par IP',
                ),
                const SizedBox(height: 8),

                // Option C
                _gpsOption(
                  emoji: '🗺️',
                  title: 'Option C — Google Maps (recommandé)',
                  subtitle:
                      'Clic droit sur le site → copiez les coordonnées → collez dans Latitude.',
                  onTap: _openGoogleMaps,
                  label: 'Ouvrir Google Maps',
                ),
              ],
            ]),

            const SizedBox(height: 32),

            // ── Bouton sauvegarder ──────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _save,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_isEdit ? Icons.save : Icons.check_circle),
                label: Text(
                  _loading
                      ? 'Enregistrement…'
                      : (_isEdit
                          ? 'Enregistrer les modifications'
                          : 'Créer le terminal'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a2540),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Widgets helpers ────────────────────────────────────────────────────────

  Widget _section(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Colors.grey,
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          decoration: _inputDeco(
              hint: hint,
              icon: icon != null
                  ? Icon(icon, size: 18, color: Colors.grey)
                  : null),
          validator: validator,
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Colors.grey,
      ),
    );
  }

  InputDecoration _inputDeco({String? hint, Widget? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13),
      prefixIcon: icon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFdee2e6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFdee2e6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF1a2540), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFc92a2a)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _gpsOption({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFdee2e6)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji $title',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1a2540),
                side: const BorderSide(color: Color(0xFFdee2e6)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFffe3e3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFffa8a8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFc92a2a), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: const TextStyle(fontSize: 13, color: Color(0xFFc92a2a))),
          ),
        ],
      ),
    );
  }
}
