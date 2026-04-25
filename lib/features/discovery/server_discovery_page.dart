import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/server_info.dart';
import '../../core/network/server_discovery.dart';
import '../../core/services/update_service.dart';
import '../home/home_page.dart';
import '../settings/update_dialog.dart';
import '../settings/settings_page.dart';

/// 服务器发现与连接页面
class ServerDiscoveryPage extends StatefulWidget {
  const ServerDiscoveryPage({super.key});

  @override
  State<ServerDiscoveryPage> createState() => _ServerDiscoveryPageState();
}

class _ServerDiscoveryPageState extends State<ServerDiscoveryPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '9527',
  );
  bool _isManualConnecting = false;

  @override
  void initState() {
    super.initState();
    // 自动开始扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
      // 启动时自动检测更新
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _startScan() {
    final appState = context.read<AppState>();
    appState.discovery.startScan();
  }

  /// 启动时自动检测更新（静默，有频率限制）
  Future<void> _checkForUpdate() async {
    final updateService = UpdateService();
    final result = await updateService.checkForUpdate();
    if (result.hasUpdate && result.release != null && mounted) {
      UpdateDialog.show(context, release: result.release!);
    }
  }

  Future<void> _connectToServer(ServerInfo server) async {
    final appState = context.read<AppState>();
    final success = await appState.connectToServer(server);
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.errorMessage ?? '连接失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _manualConnect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9527;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 IP 地址')));
      return;
    }

    setState(() => _isManualConnecting = true);
    final appState = context.read<AppState>();
    final success = await appState.connectByIp(ip, port: port);
    setState(() => _isManualConnecting = false);

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.errorMessage ?? '连接失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final discovery = appState.discovery;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comic Reader'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 自动发现区域
            _buildDiscoverySection(discovery),
            const SizedBox(height: 24),

            // 分隔线
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '或手动输入',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),

            // 手动连接区域
            _buildManualConnectSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverySection(ServerDiscovery discovery) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wifi),
            const SizedBox(width: 8),
            Text('局域网服务器', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (discovery.isScanning)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _startScan,
                tooltip: '重新扫描',
              ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<ServerInfo>(
          stream: discovery.onServerFound,
          builder: (context, snapshot) {
            final servers = discovery.discoveredServers;
            if (discovery.isScanning && servers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在扫描局域网...'),
                    ],
                  ),
                ),
              );
            }
            if (servers.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('未发现服务器', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text(
                        '请确保电脑端 Comic Reader 已启动',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: servers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final server = servers[index];
                return _ServerCard(
                  server: server,
                  onTap: () => _connectToServer(server),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildManualConnectSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link),
            const SizedBox(width: 8),
            Text('手动连接', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'IP 地址',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '9527',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isManualConnecting ? null : _manualConnect,
            icon: _isManualConnecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.connect_without_contact),
            label: Text(_isManualConnecting ? '连接中...' : '连接'),
          ),
        ),
      ],
    );
  }
}

/// 服务器卡片组件
class _ServerCard extends StatelessWidget {
  final ServerInfo server;
  final VoidCallback onTap;

  const _ServerCard({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.computer,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${server.ip}:${server.port}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
