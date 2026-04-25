import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/models/file_info.dart';

class VideoPlayerPage extends StatefulWidget {
  final FileInfo videoFile;
  final String baseUrl;

  const VideoPlayerPage({
    super.key,
    required this.videoFile,
    required this.baseUrl,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Video Player',
      ),
    );
    _controller = VideoController(_player);

    // Build the video stream URL
    final videoUrl =
        '${widget.baseUrl}/api/file?path=${Uri.encodeComponent(widget.videoFile.fullPath)}';

    // Open the video
    _player.open(Media(videoUrl));

    // Listen to player state changes
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    _player.stream.position.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() {
          _isBuffering = buffering;
        });
      }
    });

    _player.stream.completed.listen((completed) {
      if (completed) {
        WakelockPlus.disable();
      }
    });

    // Keep screen awake while playing
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _player.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _togglePlayPause() {
    _player.playOrPause();
  }

  void _seekTo(Duration position) {
    _player.seek(position);
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _cycleSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    _playbackSpeed = speeds[nextIndex];
    _player.setRate(_playbackSpeed);
    setState(() {});
  }

  void _seekRelative(Duration offset) {
    final newPosition = _position + offset;
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(
        0,
        _duration.inMilliseconds,
      ),
    );
    _seekTo(clampedPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(
                widget.videoFile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video display
                  Video(
                    controller: _controller,
                    fit: BoxFit.contain,
                  ),
                  // Buffering indicator
                  if (_isBuffering)
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  // Controls overlay
                  if (_showControls)
                    _buildControlsOverlay(context),
                ],
              ),
            ),
          ),
          // Bottom controls bar
          if (_showControls) _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Rewind 10s
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white, size: 36),
            onPressed: () => _seekRelative(const Duration(seconds: -10)),
          ),
          // Play/Pause
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 56,
            ),
            onPressed: _togglePlayPause,
          ),
          // Forward 10s
          IconButton(
            icon:
                const Icon(Icons.forward_10, color: Colors.white, size: 36),
            onPressed: () => _seekRelative(const Duration(seconds: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds /
                          _duration.inMilliseconds.toDouble()
                      : 0,
                  onChanged: (value) {
                    final newPosition = Duration(
                      milliseconds:
                          (value * _duration.inMilliseconds).round(),
                    );
                    _seekTo(newPosition);
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Colors.grey[600],
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Speed
              TextButton(
                onPressed: _cycleSpeed,
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 16),
              // Fullscreen
              IconButton(
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
