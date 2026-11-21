import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/update_service.dart';
import '../../core/services/download_service.dart';
import '../../core/state/app_state.dart';
import '../discovery/server_discovery_page.dart';
import 'update_dialog.dart';

/// 设置页面
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _currentVersion = '';
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _currentVersion = packageInfo.version;
    });
  }

  Future<void> _disconnect() async {
    final appState = context.read<AppState>();
    appState.disconnect();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ServerDiscoveryPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final server = appState.connectedServer;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 连接部分
          _buildSectionHeader(theme, '连接'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(server?.name ?? '未连接'),
            subtitle: Text(
              server != null ? '${server.ip}:${server.port}' : '未连接到服务器',
            ),
            trailing: server != null
                ? TextButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('断开'),
                  )
                : null,
          ),
          const Divider(height: 1),

          // 关于部分
          _buildSectionHeader(theme, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前版本'),
            subtitle: Text('v$_currentVersion'),
          ),
          const Divider(height: 1),

          // 更新部分
          _buildSectionHeader(theme, '更新'),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: const Text('手动检查是否有新版本'),
            trailing: _isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isChecking ? null : _checkForUpdate,
          ),
          const Divider(height: 1),

          // 存储部分
          _buildSectionHeader(theme, '存储'),
          ListTile(
            leading: const Icon(Icons.cleaning_services),
            title: const Text('清理更新缓存'),
            subtitle: const Text('删除已下载的安装包'),
            onTap: _cleanUpCache,
          ),
          const Divider(height: 1),

          // GitHub 链接
          _buildSectionHeader(theme, '链接'),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('GitHub 仓库'),
            subtitle: Text(
              '${UpdateService.githubOwner}/${UpdateService.githubRepo}',
            ),
            onTap: _openGitHub,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.new_releases),
            title: const Text('最新 Release'),
            subtitle: const Text('在浏览器中查看最新发布版本'),
            onTap: _openReleases,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isChecking = true);

    final updateService = UpdateService();
    try {
      // 手动检查时强制检查，忽略频率限制和跳过版本
      final result = await updateService.checkForUpdate(forceCheck: true);

      if (!mounted) return;

      if (result.hasUpdate && result.release != null) {
        UpdateDialog.show(context, release: result.release!);
      } else if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      updateService.dispose();
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _cleanUpCache() async {
    try {
      final downloadService = DownloadService();
      await downloadService.cleanUpApkFiles();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('缓存已清理')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清理失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openGitHub() async {
    final url = Uri.parse(
      'https://github.com/${UpdateService.githubOwner}/${UpdateService.githubRepo}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openReleases() async {
    final url = Uri.parse(
      'https://github.com/${UpdateService.githubOwner}/${UpdateService.githubRepo}/releases',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
