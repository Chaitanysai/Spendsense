import 'package:flutter/material.dart';
import '../services/secure_storage_service.dart';

/// AI Provider Settings screen for runtime API key configuration.
/// Keys are stored in platform-specific encrypted storage.
class AISettingsScreen extends StatefulWidget {
  const AISettingsScreen({super.key});

  @override
  State<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends State<AISettingsScreen> {
  final _storage = SecureStorageService();

  // Controllers for each provider
  final _groqController = TextEditingController();
  final _cerebrasController = TextEditingController();
  final _geminiController = TextEditingController();
  final _openRouterController = TextEditingController();

  // Status indicators
  bool _groqConfigured = false;
  bool _cerebrasConfigured = false;
  bool _geminiConfigured = false;
  bool _openRouterConfigured = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  @override
  void dispose() {
    _groqController.dispose();
    _cerebrasController.dispose();
    _geminiController.dispose();
    _openRouterController.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    setState(() => _loading = true);

    final groq = await _storage.getGroqKey();
    final cerebras = await _storage.getCerebrasKey();
    final gemini = await _storage.getGeminiKey();
    final openRouter = await _storage.getOpenRouterKey();

    setState(() {
      _groqConfigured = groq != null && groq.isNotEmpty;
      _cerebrasConfigured = cerebras != null && cerebras.isNotEmpty;
      _geminiConfigured = gemini != null && gemini.isNotEmpty;
      _openRouterConfigured = openRouter != null && openRouter.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _saveKey(
    String providerName,
    TextEditingController controller,
    Future<bool> Function(String) saveFn,
    Function(bool) setConfigured,
  ) async {
    final value = controller.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$providerName key cannot be empty')),
      );
      return;
    }

    final success = await saveFn(value);
    if (success) {
      setState(() => setConfigured(true));
      controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$providerName key saved securely')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save $providerName key')),
        );
      }
    }
  }

  Future<void> _clearKey(
    String providerName,
    String keyName,
    Function(bool) setConfigured,
  ) async {
    await _storage.deleteApiKey(keyName);
    setState(() => setConfigured(false));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$providerName key cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Configure API keys for AI-powered transaction parsing. '
                  'Keys are stored securely on your device and never leave your control.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Provider Chain Order: Groq → Cerebras → Gemini → OpenRouter',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // Groq
                _buildProviderSection(
                  context,
                  providerName: 'Groq',
                  description: 'Fast inference with llama-3.3-70b-versatile',
                  controller: _groqController,
                  isConfigured: _groqConfigured,
                  onSave: () => _saveKey(
                    'Groq',
                    _groqController,
                    _storage.setGroqKey,
                    (v) => _groqConfigured = v,
                  ),
                  onClear: () => _clearKey(
                    'Groq',
                    SecureStorageService.groqKeyName,
                    (v) => _groqConfigured = v,
                  ),
                ),

                const Divider(height: 32),

                // Cerebras
                _buildProviderSection(
                  context,
                  providerName: 'Cerebras',
                  description: 'Cost-effective with llama3.1-8b',
                  controller: _cerebrasController,
                  isConfigured: _cerebrasConfigured,
                  onSave: () => _saveKey(
                    'Cerebras',
                    _cerebrasController,
                    _storage.setCerebrasKey,
                    (v) => _cerebrasConfigured = v,
                  ),
                  onClear: () => _clearKey(
                    'Cerebras',
                    SecureStorageService.cerebrasKeyName,
                    (v) => _cerebrasConfigured = v,
                  ),
                ),

                const Divider(height: 32),

                // Gemini
                _buildProviderSection(
                  context,
                  providerName: 'Gemini',
                  description: 'High quality with gemini-2.5-flash',
                  controller: _geminiController,
                  isConfigured: _geminiConfigured,
                  onSave: () => _saveKey(
                    'Gemini',
                    _geminiController,
                    _storage.setGeminiKey,
                    (v) => _geminiConfigured = v,
                  ),
                  onClear: () => _clearKey(
                    'Gemini',
                    SecureStorageService.geminiKeyName,
                    (v) => _geminiConfigured = v,
                  ),
                ),

                const Divider(height: 32),

                // OpenRouter
                _buildProviderSection(
                  context,
                  providerName: 'OpenRouter',
                  description: 'Fallback with llama-3.3-70b-instruct:free',
                  controller: _openRouterController,
                  isConfigured: _openRouterConfigured,
                  onSave: () => _saveKey(
                    'OpenRouter',
                    _openRouterController,
                    _storage.setOpenRouterKey,
                    (v) => _openRouterConfigured = v,
                  ),
                  onClear: () => _clearKey(
                    'OpenRouter',
                    SecureStorageService.openRouterKeyName,
                    (v) => _openRouterConfigured = v,
                  ),
                ),

                const SizedBox(height: 32),

                // Clear all button
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear All Keys?'),
                        content: const Text(
                          'This will remove all stored API keys. You can add them again later.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await _storage.clearAll();
                      setState(() {
                        _groqConfigured = false;
                        _cerebrasConfigured = false;
                        _geminiConfigured = false;
                        _openRouterConfigured = false;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All API keys cleared'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Clear All Keys'),
                ),
              ],
            ),
    );
  }

  Widget _buildProviderSection(
    BuildContext context, {
    required String providerName,
    required String description,
    required TextEditingController controller,
    required bool isConfigured,
    required VoidCallback onSave,
    required VoidCallback onClear,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              providerName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            if (isConfigured)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  'Configured',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),
                ),
                child: Text(
                  'Not configured',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Enter API key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => controller.clear(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
            if (isConfigured)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete, size: 18),
                label: const Text('Clear'),
              ),
          ],
        ),
      ],
    );
  }
}
