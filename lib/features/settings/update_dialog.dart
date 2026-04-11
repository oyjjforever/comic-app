import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';
import '../../core/services/download_service.dart';

/// 更新对话框
/// 显示新版本信息，支持下载、安装和跳过版本
class UpdateDialog extends StatefulWidget {
  final GitHubRelease release;

  const UpdateDialog({super.key, required this.release});

  /// 显示更新对话框
  static Future<void> show(
    BuildContext context, {
    required GitHubRelease release,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(release: release),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final DownloadService _downloadService = DownloadService();
  DownloadStatus _status = DownloadStatus.idle;
  int _progress = 0;
  String? _errorMessage;

  @override
  void dispose() {
    _downloadService.cancelDownload();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '发现新版本 ${widget.release.version}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: _buildContent(theme),
      actions: _buildActions(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 更新日志
        if (widget.release.body.isNotEmpty) ...[
          Text(
            '更新内容：',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Text(
                widget.release.body,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 下载进度
        if (_status == DownloadStatus.downloading) ...[
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: _progress / 100)),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text(
                  '$_progress%',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // 安装中提示
        if (_status == DownloadStatus.installing) ...[
          const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('正在打开安装器...'),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // 错误信息
        if (_errorMessage != null) ...[
          Text(
            _errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],

        // 发布时间
        Text(
          '发布时间：${_formatDate(widget.release.publishedAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(ThemeData theme) {
    // 下载中：只显示取消按钮
    if (_status == DownloadStatus.downloading) {
      return [TextButton(onPressed: _cancelDownload, child: const Text('取消'))];
    }

    // 安装中：无按钮
    if (_status == DownloadStatus.installing) {
      return [];
    }

    // 下载失败：显示重试和跳过
    if (_status == DownloadStatus.failed) {
      return [
        TextButton(onPressed: _skipVersion, child: const Text('跳过该版本')),
        FilledButton(onPressed: _startDownload, child: const Text('重试')),
      ];
    }

    // 默认（空闲/已完成）：显示跳过和更新按钮
    return [
      TextButton(onPressed: _skipVersion, child: const Text('跳过该版本')),
      FilledButton(
        onPressed: _status == DownloadStatus.completed ? null : _startDownload,
        child: const Text('立即更新'),
      ),
    ];
  }

  Future<void> _startDownload() async {
    final apkUrl = widget.release.apkDownloadUrl;
    if (apkUrl == null) {
      setState(() {
        _errorMessage = '未找到 APK 下载链接，请前往 GitHub 手动下载';
      });
      return;
    }

    setState(() {
      _status = DownloadStatus.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    try {
      await _downloadService.downloadAndInstall(
        downloadUrl: apkUrl,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
        onStatusChanged: (status) {
          setState(() {
            _status = status;
          });
        },
      );
    } catch (e) {
      setState(() {
        _errorMessage = '下载失败: $e';
      });
    }
  }

  void _cancelDownload() {
    _downloadService.cancelDownload();
    setState(() {
      _status = DownloadStatus.idle;
      _progress = 0;
    });
  }

  Future<void> _skipVersion() async {
    final updateService = UpdateService();
    await updateService.skipVersion(widget.release.version);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
