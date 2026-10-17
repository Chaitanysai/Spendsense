import 'package:flutter/material.dart';
import '../services/secure_storage_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';

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

    if (!mounted) return;

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
    if (!mounted) return;
    if (success) {
      setState(() => setConfigured(true));
      controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$providerName key saved securely')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save $providerName key')),
      );
    }
  }

  Future<void> _clearKey(
    String providerName,
    String keyName,
    Function(bool) setConfigured,
  ) async {
    await _storage.deleteApiKey(keyName);
    if (!mounted) return;
    setState(() => setConfigured(false));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$providerName key cleared')),
    );
  }

  Future<void> _clearAllKeys() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear All Keys?'),
        content: const Text(
          'This will remove all stored API keys. You can add them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _storage.clearAll();
    if (!mounted) return;
    setState(() {
      _groqConfigured = false;
      _cerebrasConfigured = false;
      _geminiConfigured = false;
      _openRouterConfigured = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All API keys cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('AI Provider Settings'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: false,
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: AppColors.brand.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            color: AppColors.brand, size: 20),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Configure API keys for AI-powered transaction parsing. '
                            'Keys are stored securely on your device and never leave your control.',
                            style: AppText.body(context).copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Provider Chain Order: Groq → Cerebras → Gemini → OpenRouter',
                    style: AppText.label(context).copyWith(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildProviderSection(
                    context,
                    providerName: 'Groq',
                    description: 'Fast inference with llama-3.3-70b-versatile',
                    controller: _groqController,
                    isConfigured: _groqConfigured,
                    onSave: () => _saveKey('Groq', _groqController,
                        _storage.setGroqKey, (v) => _groqConfigured = v),
                    onClear: () => _clearKey(
                        'Groq',
                        SecureStorageService.groqKeyName,
                        (v) => _groqConfigured = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                        (v) => _cerebrasConfigured = v),
                    onClear: () => _clearKey(
                        'Cerebras',
                        SecureStorageService.cerebrasKeyName,
                        (v) => _cerebrasConfigured = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildProviderSection(
                    context,
                    providerName: 'Gemini',
                    description: 'High quality with gemini-2.5-flash',
                    controller: _geminiController,
                    isConfigured: _geminiConfigured,
                    onSave: () => _saveKey('Gemini', _geminiController,
                        _storage.setGeminiKey, (v) => _geminiConfigured = v),
                    onClear: () => _clearKey(
                        'Gemini',
                        SecureStorageService.geminiKeyName,
                        (v) => _geminiConfigured = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                        (v) => _openRouterConfigured = v),
                    onClear: () => _clearKey(
                        'OpenRouter',
                        SecureStorageService.openRouterKeyName,
                        (v) => _openRouterConfigured = v),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  OutlinedButton.icon(
                    onPressed: _clearAllKeys,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear All Keys'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(
                          color: AppColors.danger.withValues(alpha: 0.4)),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(providerName,
                  style: AppText.title(context).copyWith(fontSize: 15)),
              const SizedBox(width: AppSpacing.sm),
              _statusBadge(context, isConfigured),
            ],
          ),
          const SizedBox(height: 4),
          Text(description,
              style: AppText.body(context).copyWith(fontSize: 12)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter API key',
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => controller.clear(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isConfigured)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Clear'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.danger),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, bool isConfigured) {
    final color =
        isConfigured ? AppColors.incomeGreen : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        isConfigured ? 'Configured' : 'Not configured',
        style: AppText.label(context).copyWith(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
