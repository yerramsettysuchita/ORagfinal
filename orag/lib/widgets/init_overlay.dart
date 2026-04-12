import 'package:flutter/material.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';

/// Full-screen overlay shown during model download + load.
/// Blocks interaction and shows real-time progress.
class InitOverlay extends StatelessWidget {
  final InitStatus status;
  final VoidCallback? onRetry;

  const InitOverlay({
    super.key,
    required this.status,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background.withValues(alpha: 0.97),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated logo
              _AnimatedLogo(state: status.state),
              const SizedBox(height: 32),

              // Title
              Text(
                _title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle / message
              Text(
                status.message.isEmpty ? _defaultMessage : status.message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 28),

              // Progress bar (for downloading/loading)
              if (status.state == InitState.downloading ||
                  status.state == InitState.loading)
                _ProgressBar(progress: status.progress),

              // Error retry button
              if (status.isError && onRetry != null) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (status.state) {
      case InitState.idle:
        return 'Starting O-RAG';
      case InitState.downloading:
        return 'Downloading AI Model';
      case InitState.loading:
        return 'Loading AI Engine';
      case InitState.ready:
        return 'Ready!';
      case InitState.error:
        return 'Something Went Wrong';
    }
  }

  String get _defaultMessage {
    switch (status.state) {
      case InitState.idle:
        return 'Preparing the AI engine…';
      case InitState.downloading:
        return 'This only happens once. Please stay on Wi-Fi.';
      case InitState.loading:
        return 'Loading model into memory…';
      case InitState.ready:
        return 'AI is ready to chat!';
      case InitState.error:
        return 'Could not initialize the AI engine.';
    }
  }
}

// ---- Animated logo ----

class _AnimatedLogo extends StatefulWidget {
  final InitState state;
  const _AnimatedLogo({required this.state});

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isError = widget.state == InitState.error;
    final isReady = widget.state == InitState.ready;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isError
                ? null
                : RadialGradient(
                    colors: [
                      (isReady ? AppColors.success : AppColors.primary)
                          .withValues(alpha: 0.2 + 0.1 * _controller.value),
                      (isReady ? AppColors.success : AppColors.primary)
                          .withValues(alpha: 0.05),
                    ],
                  ),
            color: isError ? AppColors.error.withValues(alpha: 0.15) : null,
          ),
          child: Icon(
            isError
                ? Icons.error_outline_rounded
                : isReady
                    ? Icons.check_circle_outline_rounded
                    : Icons.auto_awesome_rounded,
            size: 40,
            color: isError
                ? AppColors.error
                : isReady
                    ? AppColors.success
                    : AppColors.primary,
          ),
        );
      },
    );
  }
}

// ---- Progress bar ----

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress > 0.01 ? progress : null, // indeterminate if ~0
            minHeight: 6,
            backgroundColor: AppColors.surfaceLight,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        if (progress > 0.01) ...[
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
