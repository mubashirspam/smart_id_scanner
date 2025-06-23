import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraState {
  uninitialized,
  initializing,
  ready,
  capturing,
  processing,
  error,
  permissionDenied,
  captured,
}

class CameraControllerService with ChangeNotifier {
  CameraController? _cameraController;
  CameraState _state = CameraState.uninitialized;
  Timer? _detectionTimer;
  String? _errorMessage;
  List<CameraDescription>? _cameras;

  // Detection parameters
  int _consecutiveDetections = 0;
  int _requiredConsecutiveDetections = 3;
  bool _isProcessingImage = false;

  // Getters
  CameraController? get cameraController => _cameraController;
  CameraState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isInitialized => _cameraController?.value.isInitialized ?? false;
  bool get isProcessing => _isProcessingImage;
  int get consecutiveDetections => _consecutiveDetections;
  int get requiredDetections => _requiredConsecutiveDetections;

  // Callbacks
  Function(File imageFile)? onImageCaptured;
  Function(String message)? onError;
  Function(int current, int required)? onDetectionProgress;

  void setDetectionCallback(Function(File imageFile) callback) {
    onImageCaptured = callback;
  }

  void setErrorCallback(Function(String message) callback) {
    onError = callback;
  }

  void setDetectionProgressCallback(
    Function(int current, int required) callback,
  ) {
    onDetectionProgress = callback;
  }

  void setRequiredDetections(int count) {
    _requiredConsecutiveDetections = count;
  }

  Future<bool> _checkAndRequestCameraPermission() async {
    final status = await Permission.camera.status;

    if (status.isDenied) {
      final result = await Permission.camera.request();
      return result.isGranted;
    }

    return status.isGranted;
  }

  Future<void> initializeCamera() async {
    _setState(CameraState.initializing);

    try {
      // Check camera permission first
      final hasPermission = await _checkAndRequestCameraPermission();
      if (!hasPermission) {
        _setState(CameraState.permissionDenied);
        _setError('Camera permission denied');
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _setError('No cameras available');
        return;
      }

      // Find back camera or use first available
      CameraDescription? selectedCamera;
      for (final camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }
      selectedCamera ??= _cameras!.first;

      // Create camera controller
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      // Initialize controller
      await _cameraController!.initialize();

      // Configure camera settings
      await _configureCameraSettings();

      _setState(CameraState.ready);
      dev.log('Camera initialized successfully');
    } catch (e) {
      _setError('Failed to initialize camera: $e');
      dev.log('Camera initialization error: $e', error: e);
    }
  }

  Future<void> _configureCameraSettings() async {
    if (_cameraController == null) return;

    try {
      // Set auto focus if available
      await _cameraController!.setFocusMode(FocusMode.auto);
    } catch (e) {
      dev.log('Could not set focus mode: $e');
    }

    try {
      // Set auto exposure if available
      await _cameraController!.setExposureMode(ExposureMode.auto);
    } catch (e) {
      dev.log('Could not set exposure mode: $e');
    }

    try {
      // Lock orientation to prevent issues
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } catch (e) {
      dev.log('Could not lock orientation: $e');
    }
  }

  void startDetection({Duration interval = const Duration(seconds: 2)}) {
    if (_state != CameraState.ready) {
      dev.log('Cannot start detection, camera state: $_state');
      return;
    }

    _detectionTimer?.cancel();

    // Start periodic capture
    _detectionTimer = Timer.periodic(interval, (timer) async {
      if (_state == CameraState.ready && !_isProcessingImage) {
        await _captureAndProcess();
      }
    });

    dev.log('Detection started with interval: ${interval.inSeconds}s');
  }

  void stopDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;

    _consecutiveDetections = 0;
    _isProcessingImage = false;
    onDetectionProgress?.call(0, _requiredConsecutiveDetections);

    dev.log('Detection stopped');
  }

  void resetDetection() {
    _consecutiveDetections = 0;
    _isProcessingImage = false;
    onDetectionProgress?.call(0, _requiredConsecutiveDetections);
    _setState(CameraState.ready);
  }

  Future<void> captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setError('Camera not initialized');
      return;
    }

    if (_state != CameraState.ready) {
      dev.log('Camera not ready for capture, current state: $_state');
      return;
    }

    _setState(CameraState.capturing);

    try {
      // Ensure flash is off
      await _cameraController!.setFlashMode(FlashMode.off);

      // Take picture
      final XFile file = await _cameraController!.takePicture();
      final imageFile = File(file.path);

      dev.log('Image captured: ${imageFile.path}');
      onImageCaptured?.call(imageFile);
      _setState(CameraState.captured);
    } catch (e) {
      _setError('Failed to capture image: $e');
      dev.log('Capture error: $e', error: e);
    } finally {
      _setState(CameraState.ready);
    }
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessingImage) {
      dev.log('Already processing image, skipping capture');
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      dev.log('Camera not initialized, skipping capture');
      return;
    }

    if (_state != CameraState.ready) {
      dev.log('Camera not ready, state: $_state');
      return;
    }

    _isProcessingImage = true;
    _setState(CameraState.processing);

    try {
      // Ensure flash is off
      await _cameraController!.setFlashMode(FlashMode.off);

      // Take picture
      final XFile file = await _cameraController!.takePicture();
      final imageFile = File(file.path);

      // Check image quality
      final bool isGoodQuality = await _checkImageQuality(imageFile);

      if (isGoodQuality) {
        _consecutiveDetections++;
        onDetectionProgress?.call(
          _consecutiveDetections,
          _requiredConsecutiveDetections,
        );

        dev.log(
          'Good image detected: $_consecutiveDetections/$_requiredConsecutiveDetections',
        );

        if (_consecutiveDetections >= _requiredConsecutiveDetections) {
          stopDetection();
          _setState(CameraState.capturing);
          onImageCaptured?.call(imageFile);
          return;
        }
      } else {
        _consecutiveDetections = 0;
        onDetectionProgress?.call(0, _requiredConsecutiveDetections);
        dev.log('Poor image quality, resetting detection count');
      }

      // Clean up temporary file if not used
      if (_consecutiveDetections < _requiredConsecutiveDetections) {
        try {
          await imageFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      _setError('Error processing image: $e');
      dev.log('Image processing error: $e', error: e);
      _consecutiveDetections = 0;
      onDetectionProgress?.call(0, _requiredConsecutiveDetections);
    } finally {
      _isProcessingImage = false;
      if (_state == CameraState.processing) {
        _setState(CameraState.ready);
      }
    }
  }

  Future<bool> _checkImageQuality(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return false;

      // Basic quality checks
      // 1. Check if image is too dark
      final brightness = _calculateAverageBrightness(image);
      if (brightness < 50) {
        dev.log('Image too dark: brightness = $brightness');
        return false;
      }

      // 2. Check for blur using Laplacian variance
      final blurScore = _calculateBlurScore(image);
      const double blurThreshold = 100.0;

      dev.log(
        'Image quality - Brightness: $brightness, Blur score: $blurScore',
      );

      return blurScore >= blurThreshold;
    } catch (e) {
      dev.log('Error checking image quality: $e');
      return false;
    }
  }

  double _calculateAverageBrightness(img.Image image) {
    double totalBrightness = 0;
    int pixelCount = 0;
    const sampleRate = 10;

    for (int y = 0; y < image.height; y += sampleRate) {
      for (int x = 0; x < image.width; x += sampleRate) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b);
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    return pixelCount > 0 ? totalBrightness / pixelCount : 0;
  }

  double _calculateBlurScore(img.Image image) {
    final grayImage = img.grayscale(image);

    const sampleRate = 4;
    int sampleCount = 0;
    double sum = 0;
    double sumSquared = 0;

    const laplacianKernel = [
      [0, 1, 0],
      [1, -4, 1],
      [0, 1, 0],
    ];

    for (int y = 1; y < grayImage.height - 1; y += sampleRate) {
      for (int x = 1; x < grayImage.width - 1; x += sampleRate) {
        double laplacian = 0;

        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = grayImage.getPixel(x + kx, y + ky);
            final pixelValue = pixel.r.toDouble();
            laplacian += pixelValue * laplacianKernel[ky + 1][kx + 1];
          }
        }

        sum += laplacian.abs();
        sumSquared += laplacian * laplacian;
        sampleCount++;
      }
    }

    if (sampleCount > 0) {
      double mean = sum / sampleCount;
      double variance = (sumSquared / sampleCount) - (mean * mean);
      return variance;
    }

    return 0;
  }

  void _setState(CameraState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _setState(CameraState.error);
    onError?.call(message);
  }

  void handleAppLifecycleChange(AppLifecycleState state) {
    final cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
        dev.log('App lifecycle: inactive');
        break;
      case AppLifecycleState.paused:
        dev.log('App lifecycle: paused');
        stopDetection();
        break;
      case AppLifecycleState.resumed:
        dev.log('App lifecycle: resumed');
        if (_state == CameraState.ready) {
          // Re-initialize if needed
          _configureCameraSettings();
        }
        break;
      case AppLifecycleState.detached:
        dev.log('App lifecycle: detached');
        break;
      default:
        break;
    }
  }

  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      _setError('No other camera available');
      return;
    }

    final currentDirection = _cameraController?.description.lensDirection;
    CameraDescription? newCamera;

    for (final camera in _cameras!) {
      if (camera.lensDirection != currentDirection) {
        newCamera = camera;
        break;
      }
    }

    if (newCamera != null) {
      await _cameraController?.dispose();

      _cameraController = CameraController(
        newCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      await _configureCameraSettings();

      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopDetection();
    _cameraController?.dispose();
    _cameraController = null;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }
}
