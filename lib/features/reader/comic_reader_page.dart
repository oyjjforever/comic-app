import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import '../../core/state/app_state.dart';
import '../../core/models/folder_info.dart';
import '../../core/models/file_info.dart';

/// Comic reader page with image preloading
/// Supports swipe navigation, pinch-to-zoom, progress bar
class ComicReaderPage extends StatefulWidget {
  final FolderInfo folder;

  const ComicReaderPage({super.key, required this.folder});

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  final PageController _pageController = PageController();
  final FocusNode _focusNode = FocusNode();
  List<FileInfo> _imageFiles = [];
  int _currentPage = 0;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showControls = true;

  /// Number of images to preload ahead of current page
  static const int _preloadAhead = 3;

  /// Number of images to preload behind current page
  static const int _preloadBehind = 1;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 键盘 / 遥控器按键：←→ 翻页，OK/回车/空格 呼出菜单
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goToPreviousPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _goToNextPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadFiles() async {
    final appState = context.read<AppState>();
    await appState.loadFiles(widget.folder.fullPath);

    if (!mounted) return;

    setState(() {
      _imageFiles = appState.files.where((f) => f.isImage).toList();
      _isLoading = false;
      _errorMessage = _imageFiles.isEmpty
          ? 'No image files in this folder'
          : null;
    });

    // Preload first few images after initial load
    if (_imageFiles.isNotEmpty) {
      _preloadAround(0);
    }
  }

  String _getImageUrl(int index) {
    final appState = context.read<AppState>();
    return appState.apiClient!.buildFileUrl(_imageFiles[index].fullPath);
  }

  /// Preload images around the given index
  void _preloadAround(int index) {
    if (!mounted || _imageFiles.isEmpty) return;

    // Preload images ahead
    for (
      int i = index + 1;
      i <= index + _preloadAhead && i < _imageFiles.length;
      i++
    ) {
      final url = _getImageUrl(i);
      precacheImage(CachedNetworkImageProvider(url), context);
    }

    // Preload images behind
    for (int i = index - 1; i >= 0 && i >= index - _preloadBehind; i--) {
      final url = _getImageUrl(i);
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _goToNextPage() {
    if (_currentPage < _imageFiles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        autofocus: true,
        child: Stack(
          children: [
            _buildContent(),
            if (_showControls) _buildTopBar(),
            if (_showControls && _imageFiles.isNotEmpty) _buildBottomBar(),
          ],
        ),
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
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTapUp: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final tapX = details.globalPosition.dx;
        final third = screenWidth / 3;

        if (tapX < third) {
          // Left third: previous page
          _goToPreviousPage();
        } else if (tapX > third * 2) {
          // Right third: next page
          _goToNextPage();
        } else {
          // Center third: toggle controls
          _toggleControls();
        }
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: _imageFiles.length,
        onPageChanged: (page) {
          setState(() => _currentPage = page);
          _preloadAround(page);
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

/// Single page image viewer with zoom support
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
                progress != null
                    ? '${(progress * 100).toInt()}%'
                    : 'Loading...',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      },
      errorBuilder: (_, _, _) {
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
