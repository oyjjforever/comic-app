import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/server_info.dart';

/// mDNS 服务发现管理器
/// 使用 multicast_dns 包在局域网中发现 Comic Reader 服务
/// 在 Android 上回退到子网扫描模式（因为 multicast_dns 不支持 Android）
class ServerDiscovery {
  static const String _serviceType = '_comic-reader._tcp';
  static const Duration _defaultScanTimeout = Duration(seconds: 10);
  static const int _defaultPort = 9527;

  final List<ServerInfo> _discoveredServers = [];
  final StreamController<ServerInfo> _controller =
      StreamController<ServerInfo>.broadcast();

  bool _isScanning = false;
  MDnsClient? _mdnsClient;

  /// 获取已发现的服务器列表
  List<ServerInfo> get discoveredServers =>
      List.unmodifiable(_discoveredServers);

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 获取发现的服务器流
  Stream<ServerInfo> get onServerFound => _controller.stream;

  /// 开始扫描局域网中的服务器
  /// 自动选择 mDNS 或子网扫描模式
  Future<void> startScan({Duration? timeout}) async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredServers.clear();

    final scanTimeout = timeout ?? _defaultScanTimeout;

    try {
      if (Platform.isAndroid) {
        // Android: 先请求权限，再进行子网扫描
        final hasPermission = await _requestAndroidPermissions();
        if (hasPermission) {
          await _scanSubnet(scanTimeout);
        } else {
          debugPrint('ServerDiscovery: 缺少必要的权限，无法扫描');
        }
      } else {
        // 桌面平台使用 mDNS
        await _scanMdns(scanTimeout);
      }
    } catch (e) {
      debugPrint('ServerDiscovery: 扫描失败 - $e');
    } finally {
      _isScanning = false;
      _mdnsClient?.stop();
      _mdnsClient = null;
    }
  }

  /// 请求 Android 运行时权限（WiFi/网络/位置）
  /// Android 13+ 需要 NEARBY_WIFI_DEVICES
  /// Android 12 及以下需要 ACCESS_FINE_LOCATION
  Future<bool> _requestAndroidPermissions() async {
    try {
      // Android 13+ (API 33): 请求 nearby devices 权限
      if (await Permission.nearbyWifiDevices.isGranted) {
        return true;
      }

      final nearbyStatus = await Permission.nearbyWifiDevices.request();
      if (nearbyStatus.isGranted) {
        return true;
      }

      // 回退: 尝试位置权限（Android 12 及以下需要）
      if (await Permission.location.isGranted) {
        return true;
      }

      final locationStatus = await Permission.location.request();
      if (locationStatus.isGranted) {
        return true;
      }

      // 检查是否永久拒绝，引导用户去设置
      if (nearbyStatus.isPermanentlyDenied ||
          locationStatus.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('ServerDiscovery: 权限请求异常 - $e');
      // 权限请求失败时仍尝试扫描（某些设备可能不需要运行时权限）
      return true;
    }
  }

  /// mDNS 扫描（桌面平台）
  Future<void> _scanMdns(Duration timeout) async {
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();

    final serviceNames = <String>[];
    final ptrSub = _mdnsClient!
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType),
        )
        .listen((ptr) {
          if (!_isScanning) return;
          serviceNames.add(ptr.domainName);
        });

    await Future.delayed(timeout);
    await ptrSub.cancel();

    for (final serviceName in serviceNames) {
      if (!_isScanning) break;
      await _resolveService(serviceName);
    }
  }

  /// 解析单个服务的 SRV 和 IP 地址记录
  Future<void> _resolveService(String serviceName) async {
    try {
      String? target;
      int port = 0;

      await for (final srv in _mdnsClient!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName),
      )) {
        target = srv.target;
        port = srv.port;
        break;
      }

      if (target == null || port == 0) return;

      await for (final ipRecord in _mdnsClient!.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(target),
      )) {
        final ip = ipRecord.address.address;
        if (ip.isNotEmpty) {
          _addServer(
            name: serviceName.replaceAll('.$_serviceType.local', ''),
            ip: ip,
            port: port,
          );
          break;
        }
      }
    } catch (_) {
      // 解析失败
    }
  }

  /// 子网扫描（Android 回退方案）
  /// 通过 Socket 连接测试发现局域网中的服务器
  Future<void> _scanSubnet(Duration timeout) async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    if (wifiIP == null || wifiIP.isEmpty) return;

    // 解析子网前缀（如 192.168.1）
    final parts = wifiIP.split('.');
    if (parts.length != 4) return;
    final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    // 并发扫描子网中的所有 IP
    final futures = <Future<void>>[];
    for (int i = 1; i <= 254 && _isScanning; i++) {
      final ip = '$subnetPrefix.$i';
      if (ip == wifiIP) continue;
      futures.add(_probeServer(ip, _defaultPort));
    }

    // 等待所有探测完成或超时
    await Future.any([
      Future.wait(futures).catchError((_) => <void>[]),
      Future.delayed(timeout),
    ]);
  }

  /// 探测指定 IP 是否运行了 Comic Reader 服务
  Future<void> _probeServer(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.destroy();

      // 端口开放，添加为候选服务器
      _addServer(name: 'Comic Reader ($ip)', ip: ip, port: port);
    } catch (_) {
      // 连接失败，跳过
    }
  }

  /// 添加发现的服务器（去重）
  void _addServer({
    required String name,
    required String ip,
    required int port,
  }) {
    final exists = _discoveredServers.any((s) => s.ip == ip && s.port == port);
    if (exists) return;

    final server = ServerInfo.fromDiscovery(name: name, ip: ip, port: port);
    _discoveredServers.add(server);
    _controller.add(server);
  }

  /// 停止扫描
  void stopScan() {
    _isScanning = false;
    _mdnsClient?.stop();
    _mdnsClient = null;
  }

  /// 清理已发现的服务器
  void clearDiscovered() {
    _discoveredServers.clear();
  }

  /// 释放资源
  void dispose() {
    stopScan();
    _controller.close();
  }
}
