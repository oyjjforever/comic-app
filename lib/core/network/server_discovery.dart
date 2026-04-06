import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/server_info.dart';

/// mDNS 服务发现管理器
/// 使用 multicast_dns 包在局域网中发现 Comic Reader 服务
/// 在 Android 上回退到子网扫描模式（因为 multicast_dns 不支持 Android)
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
        await _scanSubnet(scanTimeout);
      } else {
        await _scanMdns(scanTimeout);
      }
    } catch (e) {
      // mDNS 扫描失败，静默处理
    } finally {
      _isScanning = false;
      _mdnsClient?.stop();
      _mdnsClient = null;
    }
  }

  /// 停止扫描
  void stopScan() {
    _isScanning = false;
    _mdnsClient?.stop();
    _mdnsClient = null;
  }

  /// mDNS 扫描（桌面平台）
  Future<void> _scanMdns(Duration timeout) async {
    _mdnsClient = MDnsClient();
    await _mdnsClient!.start();

    // 1. 查找 PTR 记录（服务指针)
    final ptrStream = _mdnsClient!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(_serviceType),
    );

    // 收集所有 PTR 记录中的服务名称
    final serviceNames = <String>[];
    final ptrSub = ptrStream.listen((ptr) {
      if (!_isScanning) return;
      serviceNames.add(ptr.domainName);
    });

    // 等待扫描超时
    await Future.delayed(timeout);
    // 停止 PTR 查询
    await ptrSub.cancel();

    // 2. 对每个发现的服务名，查询 SRV 和 A 记录
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

      // 查询 SRV 记录获取目标主机和端口
      final srvStream = _mdnsClient!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName),
      );
      await for (final srv in srvStream) {
        target = srv.target;
        port = srv.port;
        break; // 取第一个有效的 SRV 记录
      }

      if (target == null || port == 0) return;

      // 查询 A 记录获取 IP 地址
      final ipStream = _mdnsClient!.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(target),
      );
      await for (final ipRecord in ipStream) {
        final ip = ipRecord.address.address;
        if (ip.isNotEmpty) {
          _addServer(
            name: serviceName.replaceAll('.$_serviceType.local', ''),
            ip: ip,
            port: port,
          );
          break; // 取第一个有效的 IP 记录
        }
      }
    } catch (_) {
      // 解析服务失败，跳过
    }
  }

  /// 子网扫描（Android 专用)
  /// 通过 HTTP 连接测试发现局域网中的服务器
  Future<void> _scanSubnet(Duration timeout) async {
    final info = NetworkInfo();
    final wifiIP = await info.getWifiIP();
    if (wifiIP == null) return;

    // 获取本机 IP 和子网
    final subnet = wifiIP.substring(0, wifiIP.lastIndexOf('.'));
    final futures = <Future<void>>[];

    for (int i = 1; i <= 255; i++) {
      final ip = '$subnet.$i';
      futures.add(_probeIp(ip, timeout));
    }

    await Future.wait(futures);
  }

  /// 探测指定 IP 是否运行了 Comic Reader 服务
  Future<void> _probeIp(String ip, Duration timeout) async {
    try {
      final socket = await Socket.connect(ip, _defaultPort, timeout: timeout);
      socket.destroy();

      _addServer(name: 'Comic Reader', ip: ip, port: _defaultPort);
    } catch (_) {
      // 连接失败，跳过
    }
  }

  /// 添加发现的服务器（去重)
  void _addServer({
    required String name,
    required String ip,
    required int port,
  }) {
    // 检查是否已存在
    final exists = _discoveredServers.any((s) => s.ip == ip && s.port == port);
    if (exists) return;

    final server = ServerInfo.fromDiscovery(name: name, ip: ip, port: port);
    _discoveredServers.add(server);
    _controller.add(server);
  }

  /// 释放资源
  void dispose() {
    _controller.close();
    _mdnsClient?.stop();
    _mdnsClient = null;
  }
}
