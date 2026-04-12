import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';

/// Slide-out panel for managing documents used in RAG.
class DocumentDrawer extends StatefulWidget {
  final PlatformService platform;

  const DocumentDrawer({super.key, required this.platform});

  @override
  State<DocumentDrawer> createState() => _DocumentDrawerState();
}

class _DocumentDrawerState extends State<DocumentDrawer> {
  List<Map<String, dynamic>> _docs = [];
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _isLoading = true);
    final docs = await widget.platform.listDocuments();
    if (mounted) {
      setState(() {
        _docs = docs;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;

    setState(() => _isUploading = true);

    final response = await widget.platform.uploadDocument(path);
    final success = response['success'] == true;
    final message = response['message'] as String? ?? '';

    if (mounted) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) _loadDocs();
    }
  }

  Future<void> _deleteDoc(int docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete document?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Remove "$name" and its chunks from the AI\'s knowledge?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.platform.deleteDocument(docId);
      _loadDocs();
    }
  }

  Future<void> _clearAll() async {
    if (_docs.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear all documents?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'This removes all documents from the AI\'s knowledge base.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.platform.clearDocuments();
      _loadDocs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_rounded,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Documents',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_docs.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                      tooltip: 'Clear all',
                      onPressed: _clearAll,
                      color: AppColors.textDim,
                    ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),

            // Upload button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _pickAndUpload,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(_isUploading ? 'Uploading…' : 'Upload PDF / TXT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            // Document list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _docs.isEmpty
                      ? _buildEmptyState()
                      : _buildDocList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 48,
            color: AppColors.textDim.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'No documents yet',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload a PDF or TXT to enable\nAI-powered document Q&A',
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDocList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _docs.length,
      separatorBuilder: (context, idx) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final doc = _docs[index];
        final name = doc['name'] as String? ?? 'Untitled';
        final chunks = doc['num_chunks'] as int? ?? 0;
        final docId = doc['id'] as int? ?? 0;
        final isPdf = name.toLowerCase().endsWith('.pdf');

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isPdf ? AppColors.error : AppColors.primary)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isPdf ? Icons.picture_as_pdf_rounded : Icons.text_snippet_rounded,
                size: 18,
                color: isPdf ? AppColors.error : AppColors.primary,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$chunks chunks',
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.textDim,
              onPressed: () => _deleteDoc(docId, name),
            ),
          ),
        );
      },
    );
  }
}
