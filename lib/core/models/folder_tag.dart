/// 目录收藏（folder tag）模型
/// 对应 Electron 端 tags 表 type='folder' 记录，树顶"已收藏"分组的数据源
class FolderTag {
  final int? id;
  final String label;
  final String folderPath;
  final String namespace;

  FolderTag({
    this.id,
    required this.label,
    required this.folderPath,
    required this.namespace,
  });

  factory FolderTag.fromJson(Map<String, dynamic> json) {
    return FolderTag(
      id: json['id'] as int?,
      label: json['label'] as String? ?? '',
      folderPath: json['folderPath'] as String? ?? '',
      namespace: json['namespace'] as String? ?? 'default',
    );
  }
}
