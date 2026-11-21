import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/server_info.dart';
import '../../core/services/update_service.dart';
import '../home/home_page.dart';
import '../settings/update_dialog.dart';
import '../settings/settings_page.dart';

/// 连接阶段
enum _ConnectPhase { tryingLast, scanning, connecting, failed }

/// 自动连接页面
/// 启动时优先直连上次服务器，失败则扫描局域网自动连接第一台发现的服务器
class ServerDiscoveryPage extends StatefulWidget {
  const ServerDiscoveryPage({super.key});

  @override
  State<ServerDiscoveryPage> createState() => _ServerDiscoveryPageState();
}

class _ServerDiscoveryPageState extends State<ServerDiscoveryPage> {
  _ConnectPhase _phase = _ConnectPhase.tryingLast;
  StreamSubscription<ServerInfo>? _serverFoundSub;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
      // 启动时自动检测更新（静默，有频率限制）
      _checkForUpdate();
    });
  }

  @override
  void dispose() {
    _serverFoundSub?.cancel();
    context.read<AppState>().discovery.stopScan();
    super.dispose();
  }

  /// 自动连接流程：上次服务器 → 扫描局域网 → 自动连接第一台
  Future<void> _autoConnect() async {
    if (!mounted) return;
    _handled = false;
    setState(() => _phase = _ConnectPhase.tryingLast);
    final appState = context.read<AppState>();

    // 1. 快速直连上次成功的服务器
    final last = await AppState.getLastServer();
    if (last != null) {
      final success = await appState.connectToServer(
        last,
        timeout: const Duration(seconds: 2),
      );
      if (success) {
        _enterHome();
        return;
      }
    }
    if (!mounted || _handled) return;

    // 2. 扫描局域网，发现服务器后自动连接
    await _scanAndConnect(appState);
  }

  Future<void> _scanAndConnect(AppState appState) async {
    setState(() => _phase = _ConnectPhase.scanning);

    _serverFoundSub?.cancel();
    _serverFoundSub = appState.discovery.onServerFound.listen((server) {
      if (_handled) return;
      _handled = true;
      _connectToServer(server);
    });

    await appState.discovery.startScan();

    // 扫描结束仍未连接成功 → 显示失败态
    if (mounted && !_handled) {
      setState(() => _phase = _ConnectPhase.failed);
    }
    await _serverFoundSub?.cancel();
    _serverFoundSub = null;
  }

  Future<void> _connectToServer(ServerInfo server) async {
    if (!mounted) return;
    setState(() => _phase = _ConnectPhase.connecting);
    final appState = context.read<AppState>();
    final success = await appState.connectToServer(server);

    if (success) {
      appState.discovery.stopScan();
      _enterHome();
    } else if (mounted && !_handled) {
      // 该服务器连接失败，继续等扫描结果
      _handled = false;
      if (mounted) setState(() => _phase = _ConnectPhase.scanning);
    }
  }

  void _enterHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  /// 启动时自动检测更新（静默，有频率限制）
  Future<void> _checkForUpdate() async {
    final updateService = UpdateService();
    try {
      final result = await updateService.checkForUpdate();
      if (result.hasUpdate && result.release != null && mounted) {
        UpdateDialog.show(context, release: result.release!);
      }
    } finally {
      updateService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusIcon(theme),
              const SizedBox(height: 24),
              Text(
                _statusText,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _statusSubtext,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_phase == _ConnectPhase.failed)
                FilledButton.icon(
                  onPressed: _autoConnect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme) {
    switch (_phase) {
      case _ConnectPhase.tryingLast:
      case _ConnectPhase.scanning:
      case _ConnectPhase.connecting:
        return SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: theme.colorScheme.primary,
          ),
        );
      case _ConnectPhase.failed:
        return Icon(
          Icons.wifi_off,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  String get _statusText {
    switch (_phase) {
      case _ConnectPhase.tryingLast:
        return '正在连接上次的服务器...';
      case _ConnectPhase.scanning:
        return '正在扫描局域网...';
      case _ConnectPhase.connecting:
        return '正在连接服务器...';
      case _ConnectPhase.failed:
        return '未发现服务器';
    }
  }

  String get _statusSubtext {
    switch (_phase) {
      case _ConnectPhase.tryingLast:
        return '尝试直连上次连接的地址';
      case _ConnectPhase.scanning:
        return '请确保电脑端 Comic Reader 已启动';
      case _ConnectPhase.connecting:
        return '即将进入';
      case _ConnectPhase.failed:
        return '请确认电脑端已启动，且手机与电脑处于同一局域网';
    }
  }
}
