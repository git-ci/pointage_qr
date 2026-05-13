import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../models/site.dart';
import 'login_screen.dart';
import 'site_form_screen.dart';
import 'success_screen.dart';
import 'terminal_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String userName;
  const DashboardScreen({super.key, required this.userName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Site> _sites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getSites();
      setState(() {
        _sites =
            data.map((j) => Site.fromJson(j as Map<String, dynamic>)).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a2540)),
            child: const Text('Déconnecter',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openNewSiteForm() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const SiteFormScreen()),
    );
    if (result != null) {
      final siteData = result['site'] as Map<String, dynamic>;
      final site = Site.fromJson(siteData);
      if (!mounted) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => SuccessScreen(site: site, isEdit: false),
            ),
          )
          .then((_) => _loadSites());
    }
  }

  void _openEditSiteForm(Site site) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => SiteFormScreen(site: site)),
    );
    if (result != null) {
      final updatedData = result['site'] as Map<String, dynamic>;
      final updated = Site.fromJson(updatedData);
      if (!mounted) return;
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => SuccessScreen(site: updated, isEdit: true),
            ),
          )
          .then((_) => _loadSites());
    }
  }

  Future<void> _confirmDeleteSite(Site site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Color(0xFFc92a2a)),
            SizedBox(width: 10),
            Text('Supprimer le terminal',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFffe3e3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFfca5a5)),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF7f1d1d), height: 1.5),
                  children: [
                    const TextSpan(
                        text: '⚠️ Vous allez supprimer le terminal '),
                    TextSpan(
                      text: site.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(
                      text: '.\nLes pointages associés seront conservés. '
                          'Cette action est irréversible.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Supprimer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc92a2a),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      final res = await ApiService.deleteSite(site.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] as String? ?? 'Terminal supprimé.'),
          backgroundColor: const Color(0xFF2b8a3e),
          duration: const Duration(seconds: 2),
        ),
      );
      _loadSites();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFc92a2a),
        ),
      );
    }
  }

  Future<void> _confirmUnbindDevice(Site site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.phonelink_erase, color: Color(0xFFc92a2a)),
            SizedBox(width: 10),
            Text('Délier l\'appareil',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'L\'appareil actuellement lié à "${site.name}" sera dissocié.',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            if (site.deviceLabel != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFf1f3f5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(site.deviceLabel!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Un autre appareil pourra ensuite être configuré comme terminal.',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.phonelink_erase, size: 16),
            label: const Text('Délier'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFc92a2a),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await ApiService.unbindDevice(site.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appareil délié avec succès.'),
          backgroundColor: Color(0xFF2b8a3e),
          duration: Duration(seconds: 2),
        ),
      );
      _loadSites();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.message), backgroundColor: const Color(0xFFc92a2a)),
      );
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('URL copiée dans le presse-papiers'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF2b8a3e),
      ),
    );
  }

  Future<void> _openTerminal(Site site) async {
    // Persister le site localement pour que le terminal redémarre sans login
    final deviceId = await DeviceService.getDeviceId();
    await DeviceService.saveTerminalSite({
      'id': site.id,
      'name': site.name,
      'city': site.city,
      'address': site.address,
      'latitude': site.latitude,
      'longitude': site.longitude,
      'radius_meters': site.radiusMeters,
      'active': site.active,
      'gps_configured': site.gpsConfigured,
      'terminal_url': site.terminalUrl,
      'token': site.token,
      'checkin_deadline': site.checkinDeadline,
      'checkout_start': site.checkoutStart,
      'device_id': deviceId,
    });
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalScreen(site: site)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf0f2f5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a2540),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🖥️ Terminaux',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              'Connecté : ${widget.userName}',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loadSites,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnecter',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewSiteForm,
        backgroundColor: const Color(0xFF1a2540),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau terminal',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1a2540)),
            SizedBox(height: 16),
            Text('Chargement des terminaux…',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Color(0xFFc92a2a)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFc92a2a))),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSites,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a2540),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_sites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🖥️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text('Aucun terminal configuré',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Appuyez sur "Nouveau terminal" pour commencer.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openNewSiteForm,
                icon: const Icon(Icons.add),
                label: const Text('Créer le premier terminal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a2540),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSites,
      color: const Color(0xFF1a2540),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _sites.length,
        itemBuilder: (_, i) => _buildSiteCard(_sites[i]),
      ),
    );
  }

  Widget _buildSiteCard(Site site) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                const Text('🖥️', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (site.city != null || site.address != null)
                        Text(
                          [site.city, site.address]
                              .where((s) => s != null && s.isNotEmpty)
                              .join(' — '),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                // Bouton modifier
                IconButton(
                  icon:
                      const Icon(Icons.edit_outlined, color: Color(0xFF1a2540)),
                  tooltip: 'Modifier',
                  onPressed: () => _openEditSiteForm(site),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Badges
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _badge(
                  site.active ? '✅ Actif' : '⏸ Inactif',
                  site.active
                      ? const Color(0xFFd3f9d8)
                      : const Color(0xFFf1f3f5),
                  site.active ? const Color(0xFF2b8a3e) : Colors.grey,
                ),
                _badge(
                  site.gpsConfigured ? '📍 GPS activé' : '📍 GPS non configuré',
                  site.gpsConfigured
                      ? const Color(0xFFd3f9d8)
                      : const Color(0xFFfff3bf),
                  site.gpsConfigured
                      ? const Color(0xFF2b8a3e)
                      : const Color(0xFFe67700),
                ),
                if (site.gpsConfigured)
                  _badge(
                    'Rayon : ${site.radiusMeters} m',
                    const Color(0xFFe7f5ff),
                    const Color(0xFF1864ab),
                  ),
                // Badge appareil lié
                if (site.deviceBound)
                  _badge(
                    '📱 ${site.deviceLabel ?? 'Appareil lié'}',
                    const Color(0xFFf3d9fa),
                    const Color(0xFF6741d9),
                  )
                else
                  _badge(
                    '📱 Aucun appareil lié',
                    const Color(0xFFf1f3f5),
                    Colors.grey,
                  ),
                // Heure limite de pointage
                _badge(
                  '⏰ Limite : ${site.checkinDeadline}',
                  const Color(0xFFe7f5ff),
                  const Color(0xFF1864ab),
                ),
              ],
            ),

            // Bouton délier l'appareil (si lié)
            if (site.deviceBound) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _confirmUnbindDevice(site),
                icon: const Icon(Icons.phonelink_erase,
                    size: 14, color: Color(0xFFc92a2a)),
                label: const Text('Délier l\'appareil actuel',
                    style: TextStyle(fontSize: 12, color: Color(0xFFc92a2a))),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ],
            const SizedBox(height: 12),

            // URL Terminal
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFf8f9fa),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFdee2e6)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      site.terminalUrl,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF495057),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyUrl(site.terminalUrl),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copier l\'URL',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1a2540),
                      side: const BorderSide(color: Color(0xFFdee2e6)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openTerminal(site),
                    icon: const Icon(Icons.qr_code_2, size: 14),
                    label:
                        const Text('Terminal', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2d3f6b),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Bouton supprimer
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () => _confirmDeleteSite(site),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFffe3e3),
                      foregroundColor: const Color(0xFFc92a2a),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFfca5a5)),
                      ),
                    ),
                    child: const Icon(Icons.delete_outline, size: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
