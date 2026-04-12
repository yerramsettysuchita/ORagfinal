import 'package:flutter/material.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';

/// Settings & engine health screen.
class SettingsScreen extends StatefulWidget {
  final PlatformService platform;
  final VoidCallback onClearChat;

  const SettingsScreen({
    super.key,
    required this.platform,
    required this.onClearChat,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _health = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    setState(() => _loading = true);
    final h = await widget.platform.getEngineHealth();
    if (mounted) {
      setState(() {
        _health = h;
        _loading = false;
      });
    }
  }

  Future<void> _clearDocs() async {
    final confirmed = await _showConfirm(
      'Clear all documents?',
      'This removes all documents and chunks from the AI\'s knowledge base.',
    );
    if (confirmed) {
      await widget.platform.clearDocuments();
      _loadHealth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All documents cleared'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await _showConfirm(
      'Clear conversation?',
      'This will erase all chat messages and conversation memory.',
    );
    if (confirmed) {
      widget.onClearChat();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversation cleared'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<bool> _showConfirm(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title,
                style: const TextStyle(color: AppColors.textPrimary)),
            content: Text(content,
                style: const TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: _loadHealth,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      children: [
                        _buildEngineSection(),
                        const SizedBox(height: 16),
                        _buildDocumentsSection(),
                        const SizedBox(height: 16),
                        _buildActionsSection(),
                        const SizedBox(height: 16),
                        _buildAboutSection(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 4,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: AppColors.textPrimary,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.settings_rounded,
                size: 17, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Text(
            'Settings',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 21),
            color: AppColors.textSecondary,
            onPressed: _loadHealth,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  // ---- Sections ----

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildRow(String label, String value,
      {Color? valueColor, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5),
            ),
          ),
          ?trailing,
          if (trailing == null)
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor ?? AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusDot(bool active) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.success : AppColors.error,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          active ? 'Online' : 'Offline',
          style: TextStyle(
            color: active ? AppColors.success : AppColors.error,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return const Divider(color: AppColors.divider, height: 1);
  }

  // ---- Engine ----

  Widget _buildEngineSection() {
    final modelName =
        (_health['model_name'] as String?)?.replaceAll('.gguf', '') ?? '—';
    final backend = _health['backend'] as String? ?? '—';
    final qwenReady = _health['qwen_ready'] == true;
    final nomicReady = _health['nomic_ready'] == true;
    final modelLoaded = _health['model_loaded'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'AI Engine', Icons.memory_rounded, AppColors.primary),
        _buildCard(children: [
          _buildRow('Model', modelLoaded ? modelName : 'Not loaded',
              valueColor: modelLoaded ? null : AppColors.textDim),
          _divider(),
          _buildRow('Backend', backend),
          _divider(),
          _buildRow('Chat Server (Qwen)', '',
              trailing: _statusDot(qwenReady)),
          _divider(),
          _buildRow('Embedding Server (Nomic)', '',
              trailing: _statusDot(nomicReady)),
        ]),
      ],
    );
  }

  // ---- Documents ----

  Widget _buildDocumentsSection() {
    final docCount = _health['doc_count'] as int? ?? 0;
    final chunkCount = _health['chunk_count'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'Knowledge Base', Icons.folder_rounded, AppColors.secondary),
        _buildCard(children: [
          _buildRow('Documents', '$docCount'),
          _divider(),
          _buildRow('Total Chunks', '$chunkCount'),
        ]),
      ],
    );
  }

  // ---- Actions ----

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'Data Management', Icons.storage_rounded, AppColors.warning),
        _buildCard(children: [
          _buildActionRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Clear Conversation',
            subtitle: 'Erase all chat messages',
            onTap: _clearChat,
          ),
          _divider(),
          _buildActionRow(
            icon: Icons.folder_delete_outlined,
            label: 'Clear All Documents',
            subtitle: 'Remove all ingested documents & chunks',
            onTap: _clearDocs,
            destructive: true,
          ),
        ]),
      ],
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  // ---- About ----

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
            'About', Icons.info_outline_rounded, AppColors.textSecondary),
        _buildCard(children: [
          _buildRow('App', 'O-RAG'),
          _divider(),
          _buildRow('Version', '1.0.0'),
          _divider(),
          _buildRow('Engine', 'Qwen 2.5 + Nomic Embed'),
          _divider(),
          _buildRow('Platform', 'On-device (offline)'),
        ]),
      ],
    );
  }
}
