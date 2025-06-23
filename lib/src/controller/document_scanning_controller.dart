
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_cropping_utility.dart';
import '../services/service.dart';

typedef OnImageCapturedCallback =
    void Function(Map<String, dynamic> extractedData, File imageFile);
typedef OnConfirmCallback =
    void Function(Map<String, dynamic> extractedData, File imageFile);

class DocumentScanningController {
    final List<VoidCallback> _stateListeners = [];
  final List<String> validationKeywords;
  final List<ExtractedDataModel> fieldsToExtract;
  final double cameraAspectRatio;
  final bool autoCapture;
  final OnImageCapturedCallback? onImageCaptured;
  final OnConfirmCallback? onConfirm;
  final Function(String)? onError;
  final int requiredDetections;

  // Button styling
  final ButtonStyle? confirmButtonStyle;
  final ButtonStyle? retakeButtonStyle;
  final Widget? confirmButtonChild;
  final Widget? retakeButtonChild;

  // Additional options
  final bool showExtractedDataPreview;
  final Duration detectionInterval;

  late final TextExtractionService _textExtractionService;
  late final DocumentScannerService _documentScannerService;
  late final CameraControllerService _cameraControllerService;

  // Store current captured image and data
  File? _currentImageFile;
  Map<String, dynamic>? _currentExtractedData;

  DocumentScanningController({
    required this.validationKeywords,
    required this.fieldsToExtract,
    this.cameraAspectRatio = 16 / 9,
    this.autoCapture = true,
    this.onImageCaptured,
    this.onConfirm,
    this.onError,
    this.requiredDetections = 3,
    this.confirmButtonStyle,
    this.retakeButtonStyle,
    this.confirmButtonChild,
    this.retakeButtonChild,
    this.showExtractedDataPreview = true,
    this.detectionInterval = const Duration(seconds: 2),
  }) {
    _initializeServices();
  }

  void _initializeServices() {
    _textExtractionService = TextExtractionService();
    _documentScannerService = DocumentScannerService(_textExtractionService);
    _cameraControllerService = CameraControllerService();

    _cameraControllerService.setRequiredDetections(requiredDetections);
    _cameraControllerService.setDetectionCallback(_handleImageCaptured);
    _cameraControllerService.setErrorCallback(_handleError);
  }

  CameraControllerService get cameraService => _cameraControllerService;
  File? get currentImageFile => _currentImageFile;
  Map<String, dynamic>? get currentExtractedData => _currentExtractedData;
  bool get hasCapture =>
      _currentImageFile != null && _currentExtractedData != null;


      

  Future<void> initialize() async {
    await _cameraControllerService.initializeCamera();
    if (autoCapture) {
      startAutoCapture();
    }
  }

  void startAutoCapture() {
    _cameraControllerService.startDetection(interval: detectionInterval);
  }

  void stopAutoCapture() {
    _cameraControllerService.stopDetection();
  }

  Future<void> captureManually() async {
    await _cameraControllerService.captureImage();
  }

  void retake() {
    // Clean up current image
    if (_currentImageFile != null) {
      try {
        _currentImageFile!.delete();
      } catch (_) {}
    }

    _currentImageFile = null;
    _currentExtractedData = null;

    // Reset the camera state to ready to allow new captures
    _cameraControllerService.resetDetection();

    if (autoCapture) {
      // Start a new capture immediately
      _cameraControllerService.captureImage().then((_) {
        // After capture, restart auto-capture if needed
        if (autoCapture) {
          _cameraControllerService.resetDetection();
          startAutoCapture();
        }
      });
    }
  }

  void confirm() {
    if (_currentImageFile != null && _currentExtractedData != null) {
      onConfirm?.call(_currentExtractedData!, _currentImageFile!);
    }
  }
 void addStateListener(VoidCallback listener) {
    _stateListeners.add(listener);
  }
  
  void removeStateListener(VoidCallback listener) {
    _stateListeners.remove(listener);
  }
  
  void _notifyStateListeners() {
    for (final listener in _stateListeners) {
      listener();
    }
  }
  
  // Update _handleImageCaptured to notify listeners
  void _handleImageCaptured(File imageFile) async {
    try {
      final croppedImage = await ImageCroppingUtility.cropImageToAspectRatio(
        imageFile,
        cameraAspectRatio,
      );
      
      final result = await _documentScannerService.scanDocument(
        imageFile: croppedImage,
        validationKeywords: validationKeywords,
        fieldsToExtract: fieldsToExtract,
      );
      
      if (result != null && result.isValid) {
        _currentImageFile = croppedImage;
        _currentExtractedData = result.toMap();
        onImageCaptured?.call(result.toMap(), croppedImage);
        
        // Notify listeners that state has changed
        _notifyStateListeners();
      } else {
        _handleError(result?.errorMessage ?? 'Document validation failed');
        try {
          await croppedImage.delete();
        } catch (_) {}
      }
    } catch (e) {
      _handleError('Error processing document: $e');
    }
  }


  void _handleError(String message) {
    onError?.call(message);
  }

  void dispose() {
    // Clean up any remaining image files
    if (_currentImageFile != null) {
      try {
        _currentImageFile!.delete();
      } catch (_) {}
    }

    _cameraControllerService.dispose();
    _documentScannerService.dispose();
  }
}
