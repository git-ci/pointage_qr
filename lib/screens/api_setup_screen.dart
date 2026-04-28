import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_logo.dart';
import 'login_screen.dart';

class ApiSetupScreen extends StatefulWidget {
  const ApiSetupScreen({super.key});

  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final url = _controller.text.trim();

    // Test de connexion
    final ok = await ApiService.testConnection(url);
    if (!ok) {
      setState(() {
        _loading = false;
        _error =
            'Impossible de joindre ce serveur. Vérifiez l\'URL et que le backend est démarré.';
      });
      return;
    }

    await ApiService.saveApiUrl(url);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a2540),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icône
                    const AppLogo(
                      size: 72,
                      showName: false,
                      darkBackground: false,
                    ),
                    const SizedBox(height: 12),

                    // Titre
                    const Text(
                      'Configuration initiale',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1a2540),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Renseignez l\'adresse de votre serveur pour continuer.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Champ URL
                    _label('URL du serveur API'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _controller,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: _inputDeco(
                        hint: 'http://192.168.1.100:8000',
                        prefix: const Icon(Icons.link,
                            size: 18, color: Colors.grey),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Ce champ est obligatoire.';
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null || !uri.hasScheme)
                          return 'URL invalide (ex: http://192.168.1.100:8000)';
                        return null;
                      },
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 8),

                    // Aide
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFe7f5ff),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '💡 Exemples :\n'
                        '• http://192.168.1.10:8000\n'
                        '• https://monserveur.monentreprise.com\n\n'
                        'Ne pas inclure /api/v1 à la fin.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF1864ab)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Erreur
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFffe3e3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFc92a2a),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Bouton
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1a2540),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Tester et continuer',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

  InputDecoration _inputDeco({String? hint, Widget? prefix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefix,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
