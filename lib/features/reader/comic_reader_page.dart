import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import '../../core/state/app_state.dart';
import '../../core/models/folder_info.dart';
import '../../core/models/file_info.dart';

/// 漫画阅读器页面
/// 支持左右滑动翻页、双指缩放、进度条
class ComicReaderPage extends StatefulWidget {
  final FolderInfo folder;

  const ComicReaderPage({super.key, required this.folder});

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  final PageController _pageController = PageController();
  List<FileInfo> _imageFiles = [];
  int _currentPage = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final appState = context.read<AppState>();
    await appState.loadFiles(widget.folder.fullPath);

    if (!mounted) return;

    setState(() {
      _imageFiles = appState.files.where((f) => f.isImage).toList();
      _isLoading = false;
      _errorMessage = _imageFiles.isEmpty ? '该文件夹中没有图片文件' : null;
    });
  }

  String _getImageUrl(int index) {
    final appState = context.read<AppState>();
    return appState.apiClient!.buildFileUrl(_imageFiles[index].fullPath);
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 主内容区域
          _buildContent(),

          // 顶部控制栏
          if (_showControls) _buildTopBar(),

          // 底部进度条
          if (_showControls && _imageFiles.isNotEmpty) _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadFiles();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _imageFiles.length,
        onPageChanged: (page) {
          setState(() => _currentPage = page);
        },
        itemBuilder: (context, index) {
          final imageUrl = _getImageUrl(index);
          return _ImageViewer(
            imageUrl: imageUrl,
            fileName: _imageFiles[index].name,
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              widget.folder.name,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            centerTitle: true,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              Row(
                children: [
                  Text(
                    '${_currentPage + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: (_currentPage + 1).toDouble(),
                      min: 1,
                      max: _imageFiles.length.toDouble(),
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Colors.white24,
                      onChanged: (value) {
                        final page = (value - 1).round();
                        _pageController.animateToPage(
                          page,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                  Text(
                    '${_imageFiles.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              // 文件名
              Text(
                _imageFiles[_currentPage].name,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单页图片查看器（支持缩放）
class _ImageViewer extends StatefulWidget {
  final String imageUrl;
  final String fileName;

  const _ImageViewer({required this.imageUrl, required this.fileName});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, color: Colors.white54, size: 48),
            const SizedBox(height: 8),
            Text(
              widget.fileName,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return PhotoView(
      imageProvider: CachedNetworkImageProvider(widget.imageUrl),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3.0,
      loadingBuilder: (_, event) {
        final progress = event?.expectedTotalBytes != null
            ? event!.cumulativeBytesLoaded / event.expectedTotalBytes!
            : null;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(value: progress, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                progress != null ? '${(progress * 100).toInt()}%' : '加载中...',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      },
      errorBuilder: (_, _, _) {
        // 延迟设置状态避免在构建中调用 setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _hasError = true);
        });
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }
}
