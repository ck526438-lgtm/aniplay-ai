import 'package:flutter/material.dart';

import '../services/backend_launcher.dart';

/// Réglage du serveur IA AniPlay (backend sur un PC, Docker, VPS…).
///
/// Sur Android, l'IA locale ne peut pas tourner sur le téléphone : on peut soit rester
/// en mode autonome (skip via AniSkip), soit pointer vers un PC qui exécute le backend.
class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key, required this.launcher});

  final BackendLauncher launcher;

  static Future<void> show(BuildContext context, BackendLauncher launcher) => showDialog<void>(
        context: context,
        builder: (_) => ServerSettingsDialog(launcher: launcher),
      );

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final _url = TextEditingController(text: widget.launcher.serverUrl ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _apply(String? value) async {
    if (value != null && value.trim().isNotEmpty && BackendLauncher.normalizeUrl(value) == null) {
      setState(() => _error = 'Adresse invalide (ex. 192.168.1.20:8000)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.launcher.setServerUrl(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.launcher.isReady || value == null || value.trim().isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.launcher.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = BackendLauncher.isMobile;
    return AlertDialog(
      title: const Text('Serveur IA'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mobile
                  ? 'Sans serveur, le skip des génériques fonctionne via AniSkip. Pour la '
                      "détection IA et les sous-titres, lancez AniPlay AI (ou le backend) sur "
                      'un PC du même Wi-Fi et saisissez son adresse.'
                  : "Laissez vide pour utiliser le moteur IA intégré. Renseignez une adresse "
                      'pour utiliser un autre serveur (Docker, autre PC…).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Adresse du serveur',
                hintText: '192.168.1.20:8000',
                prefixIcon: const Icon(Icons.dns_outlined),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: _apply,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _apply(null),
          child: Text(mobile ? 'Mode autonome' : 'Moteur intégré'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _apply(_url.text),
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connecter'),
        ),
      ],
    );
  }
}
