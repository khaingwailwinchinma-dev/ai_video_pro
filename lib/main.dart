import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_video/return_code.dart';
import 'package:gal/gal.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:permission_handler/permission_handler.dart'; 

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoApp());
}

class VideoApp extends StatelessWidget {
  const VideoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const VideoEditorScreen(),
    );
  }
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});
  @override
  _VideoEditorScreenState createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;
  File? _videoFile;
  double _playSegment = 3.0;    
  double _freezeDuration = 5.0; 
  double _blurIntensity = 10.0;
  double _blurWidth = 150.0;
  double _blurHeight = 80.0;
  double _blurOpacity = 0.6; 
  double _borderOpacity = 0.5; 
  Offset _blurPosition = const Offset(50, 200); 
  bool _isMirrored = false;
  double _selectedAspectRatio = 9 / 16;
  bool _isBlurEnabled = true; 
  bool _isBlurColorEnabled = false; 
  Color _selectedBlurColor = Colors.black; 
  bool _isExporting = false;
  final List<Color> _colorPalette = [Colors.black, Colors.white, Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple, Colors.orange];
  double _zoomLevel = 1.0;
  bool _isFreezing = false;
  double _nextTriggerTime = 0.0; 
  Timer? _logicTimer;

  Future<void> _pickVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        _videoFile = File(result.files.single.path!);
        if (_controller != null) await _controller!.dispose();
        _controller = VideoPlayerController.file(_videoFile!)
          ..initialize().then((_) { _resetCycle(); setState(() {}); });
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  // --- CapCut Style Fast Hardware Export ---
  Future<void> _exportVideo() async {
    if (_videoFile == null) return;
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.videos.request();
    }
    setState(() => _isExporting = true);
    final directory = await getTemporaryDirectory();
    final outputPath = "${directory.path}/ai_pro_edit_${DateTime.now().millisecondsSinceEpoch}.mp4";
    String hexColor = _selectedBlurColor.value.toRadixString(16).padLeft(8, '0').substring(2);
    String vf = "";
    if (_isMirrored) vf += "hflip,";
    if (_isBlurEnabled) {
      vf += "drawbox=x=${_blurPosition.dx.toInt()}:y=${_blurPosition.dy.toInt()}:w=${_blurWidth.toInt()}:h=${_blurHeight.toInt()}:color=0x$hexColor@$_blurOpacity:t=fill,";
      vf += "boxblur=$_blurIntensity";
    }
    if (vf.endsWith(",")) vf = vf.substring(0, vf.length - 1);
    if (vf.isEmpty) vf = "null";
    
    // Hardware Encoder သုံးခြင်း (အမြန်ဆုံးနည်းလမ်း)
    String hardwareEncoder = Platform.isAndroid ? "h264_mediacodec" : "h264_videotoolbox";
    String command = "-i \"${_videoFile!.path}\" -vf \"$vf\" -c:v $hardwareEncoder -preset ultrafast -y \"$outputPath\"";

    await FFmpegKit.execute(command).then((session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        await Gal.putVideo(outputPath);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved to Gallery! ✨"), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export Error!")));
      }
      setState(() => _isExporting = false);
    });
  }

  void _startEffectLogic() {
    _logicTimer?.cancel();
    _logicTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_controller == null || !_controller!.value.isInitialized || _isFreezing) return;
      double currentPos = _controller!.value.position.inMilliseconds / 1000;
      if (currentPos >= _nextTriggerTime) _triggerUltraSlowZoom();
      if (_controller!.value.position >= _controller!.value.duration) _resetCycle();
    });
  }

  void _triggerUltraSlowZoom() {
    setState(() { _isFreezing = true; _zoomLevel = 1.0; });
    _controller!.pause(); 
    const int refreshInterval = 10; 
    int steps = (_freezeDuration * 1000) ~/ refreshInterval;
    double zoomPerStep = (1.05 - 1.0) / steps;
    int currentStep = 0;
    Timer.periodic(const Duration(milliseconds: refreshInterval), (zTimer) {
      if (!mounted || !_isFreezing) { zTimer.cancel(); return; }
      if (currentStep < steps) { setState(() => _zoomLevel += zoomPerStep); currentStep++; }
      else {
        zTimer.cancel();
        setState(() {
          _zoomLevel = 1.0; _isFreezing = false;
          _nextTriggerTime = (_controller!.value.position.inMilliseconds / 1000) + _playSegment;
          _controller!.play(); 
        });
      }
    });
  }

  void _resetCycle() {
    setState(() { _zoomLevel = 1.0; _isFreezing = false; _nextTriggerTime = _playSegment; });
    _controller?.seekTo(Duration.zero);
    _controller?.play();
    _startEffectLogic();
  }

  @override
  void dispose() { _logicTimer?.cancel(); _controller?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI Professional Editor Clean")),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: Center(
                child: _controller != null && _controller!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _selectedAspectRatio, 
                        child: GestureDetector(
                          onTap: () => setState(() => _controller!.value.isPlaying ? _controller!.pause() : _controller!.play()),
                          child: ClipRect(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..scale(_zoomLevel, _zoomLevel)..rotateY(_isMirrored ? 3.14159 : 0),
                              child: Stack( fit: StackFit.expand, children: [
                                FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller!.value.size.width, height: _controller!.value.size.height, child: VideoPlayer(_controller!))),
                                if (_isBlurEnabled) Positioned(
                                  left: _blurPosition.dx, top: _blurPosition.dy,
                                  child: GestureDetector(
                                    onPanUpdate: (d) => setState(() => _blurPosition += d.delta),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: _blurIntensity, sigmaY: _blurIntensity),
                                      child: Container( width: _blurWidth, height: _blurHeight, decoration: BoxDecoration(color: _isBlurColorEnabled ? _selectedBlurColor.withOpacity(_blurOpacity) : Colors.white12, border: Border.all(color: Colors.white.withOpacity(_borderOpacity))), ),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ) : ElevatedButton(onPressed: _pickVideo, child: const Text("Pick Video")),
              ),
            ),
          ),
          _buildBottomUI(),
        ],
      ),
    );
  }

  Widget _buildBottomUI() {
    return Container(
      color: const Color(0xFF151515), padding: const EdgeInsets.all(16),
      child: Column( children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_ratioButton("9:16", 9/16), _ratioButton("4:5", 4/5), _ratioButton("1:1", 1/1), _ratioButton("16:9", 16/9)])),
        _buildS("Blur Intensity", _blurIntensity, 0, 50, (v) => setState(() => _blurIntensity = v)),
        Row( mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: () => setState(() => _isBlurEnabled = !_isBlurEnabled), icon: const Icon(Icons.blur_on)),
          IconButton(onPressed: () => setState(() => _isMirrored = !_isMirrored), icon: const Icon(Icons.flip)),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportVideo,
            icon: _isExporting ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
            label: Text(_isExporting ? "Saving..." : "Save Gallery"),
          ),
        ]),
      ]),
    );
  }

  Widget _ratioButton(String l, double r) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(l, style: const TextStyle(fontSize: 10)), selected: _selectedAspectRatio == r, onSelected: (v) => setState(() => _selectedAspectRatio = r)));
  Widget _buildS(String t, double v, double min, double max, ValueChanged<double> cb) => Row(children: [SizedBox(width: 120, child: Text(t, style: const TextStyle(fontSize: 10, color: Colors.grey))), Expanded(child: Slider(value: v, min: min, max: max, onChanged: cb)), Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10))]);
}