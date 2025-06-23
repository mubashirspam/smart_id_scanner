import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../controller/document_scanning_controller.dart';
import '../services/service.dart';

class ScannerWidget extends StatefulWidget {
  final DocumentScanningController controller;

  const ScannerWidget({super.key, required this.controller});

  @override
  State<ScannerWidget> createState() => _ScannerWidgetState();
}

class _ScannerWidgetState extends State<ScannerWidget>
    with WidgetsBindingObserver {
  late final DocumentScanningController _controller;
  bool _isInitialized = false;
  bool _showConfirmation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller;
    _controller.addStateListener(_handleControllerStateChange);
    _initializeCamera();
  }

  void _handleControllerStateChange() {
    if (_controller.currentImageFile != null && mounted) {
      setState(() {
        _showConfirmation = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStateListener(_handleControllerStateChange);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.cameraService.handleAppLifecycleChange(state);
  }

  Future<void> _initializeCamera() async {
    await _controller.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _handleRetake() {
    setState(() {
      _showConfirmation = false;
    });
    _controller.retake();
  }

  void _handleConfirm() {
    _controller.confirm();
    setState(() {
      _showConfirmation = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller.cameraService,
      builder: (context, _) {
        final cameraService = _controller.cameraService;

        // Show loading while initializing
        if (!_isInitialized ||
            cameraService.state == CameraState.uninitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        // Show error state
        if (cameraService.state == CameraState.error) {
          return _buildErrorView(cameraService);
        }

        // Show permission denied state
        if (cameraService.state == CameraState.permissionDenied) {
          return _buildPermissionDeniedView();
        }

        // Show confirmation view when image is captured
        if (_showConfirmation && _controller.currentImageFile != null) {
          return _buildConfirmationView();
        }

        // Show camera preview
        return Stack(
          children: [_buildCameraPreview(), _buildOverlay(), _buildControls()],
        );
      },
    );
  }

  Widget _buildErrorView(CameraControllerService cameraService) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              cameraService.errorMessage ?? 'Camera error',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Please grant camera permission to scan documents.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.settings),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationView() {
    if (_controller.currentImageFile == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Display captured image
        Center(
          child: AspectRatio(
            aspectRatio: _controller.cameraAspectRatio,
            child: Image.file(
              _controller.currentImageFile!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      'Error loading image',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Gradient overlay for better visibility
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.3),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.8),
              ],
              stops: const [0.0, 0.2, 0.7, 1.0],
            ),
          ),
        ),

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Row(
              children: [
                // Retake button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleRetake,
                    style:
                        _controller.retakeButtonStyle ??
                        ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                    child:
                        _controller.retakeButtonChild ??
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.refresh, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Retake',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
                const SizedBox(width: 16),
                // Confirm button
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleConfirm,
                    style:
                        _controller.confirmButtonStyle ??
                        ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                        ),
                    child:
                        _controller.confirmButtonChild ??
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.check, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Confirm',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview() {
    final cameraController = _controller.cameraService.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return Container(color: Colors.black);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: AspectRatio(
            aspectRatio: _controller.cameraAspectRatio,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController.value.previewSize!.height,
                    height: cameraController.value.previewSize!.width,
                    child: CameraPreview(cameraController),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayWidth = constraints.maxWidth * 0.9;
        final overlayHeight = overlayWidth / _controller.cameraAspectRatio;

        return Stack(
          children: [
            // Semi-transparent overlay
            Container(color: Colors.black.withValues(alpha: 0.4)),
            // Clear scanning area with animated border
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: overlayWidth,
                height: overlayHeight,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(
                    color:
                        _controller.cameraService.state ==
                                CameraState.processing
                            ? Colors.blue
                            : Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // Corner indicators
            Center(
              child: SizedBox(
                width: overlayWidth,
                height: overlayHeight,
                child: Stack(
                  children: [
                    // Top-left
                    Positioned(
                      top: 0,
                      left: 0,
                      child: _buildCornerIndicator(
                        alignment: Alignment.topLeft,
                      ),
                    ),
                    // Top-right
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _buildCornerIndicator(
                        alignment: Alignment.topRight,
                      ),
                    ),
                    // Bottom-left
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: _buildCornerIndicator(
                        alignment: Alignment.bottomLeft,
                      ),
                    ),
                    // Bottom-right
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: _buildCornerIndicator(
                        alignment: Alignment.bottomRight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCornerIndicator({required Alignment alignment}) {
    const size = 30.0;
    const thickness = 4.0;
    final color =
        _controller.cameraService.state == CameraState.processing
            ? Colors.blue
            : Colors.white;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Horizontal line
          Positioned(
            top: alignment.y < 0 ? 0 : null,
            bottom: alignment.y > 0 ? 0 : null,
            left: alignment.x < 0 ? 0 : null,
            right: alignment.x > 0 ? 0 : null,
            child: Container(
              width: alignment.x == 0 ? thickness : size,
              height: thickness,
              color: color,
            ),
          ),
          // Vertical line
          Positioned(
            top: alignment.y < 0 ? 0 : null,
            bottom: alignment.y > 0 ? 0 : null,
            left: alignment.x < 0 ? 0 : null,
            right: alignment.x > 0 ? 0 : null,
            child: Container(
              width: thickness,
              height: alignment.y == 0 ? thickness : size,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final cameraService = _controller.cameraService;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.autoCapture &&
                (cameraService.state == CameraState.processing ||
                    cameraService.consecutiveDetections > 0))
              _buildDetectionProgress(),
            if (_controller.autoCapture &&
                cameraService.consecutiveDetections > 0)
              const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 16),
            _buildStatusText(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionProgress() {
    final cameraService = _controller.cameraService;
    final progress =
        cameraService.consecutiveDetections / cameraService.requiredDetections;

    return Column(
      children: [
        Text(
          'Detecting document...',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${cameraService.consecutiveDetections} / ${cameraService.requiredDetections}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final cameraService = _controller.cameraService;

    if (!_controller.autoCapture) {
      return Center(
        child: FloatingActionButton(
          onPressed:
              cameraService.state == CameraState.ready
                  ? () => _controller.captureManually()
                  : null,
          backgroundColor:
              cameraService.state == CameraState.ready
                  ? Theme.of(context).primaryColor
                  : Colors.grey,
          child: const Icon(Icons.camera_alt, size: 28),
        ),
      );
    }

    // Auto-capture mode buttons
    if (cameraService.state == CameraState.ready &&
        cameraService.consecutiveDetections == 0) {
      return ElevatedButton.icon(
        onPressed: () => _controller.startAutoCapture(),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Scanning'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    }

    if (cameraService.state == CameraState.processing ||
        cameraService.consecutiveDetections > 0) {
      return OutlinedButton.icon(
        onPressed: () {
          _controller.stopAutoCapture();
          _controller.cameraService.resetDetection();
        },
        icon: const Icon(Icons.stop, color: Colors.red),
        label: const Text('Stop', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStatusText() {
    final cameraService = _controller.cameraService;
    String statusText = '';

    switch (cameraService.state) {
      case CameraState.ready:
        if (_controller.autoCapture) {
          statusText =
              cameraService.consecutiveDetections > 0
                  ? 'Hold steady...'
                  : 'Position document in frame';
        } else {
          statusText = 'Tap to capture';
        }
        break;
      case CameraState.processing:
        statusText = 'Analyzing...';
        break;
      case CameraState.capturing:
        statusText = 'Capturing...';
        break;
      default:
        statusText = '';
    }

    if (statusText.isEmpty) return const SizedBox.shrink();

    return Text(
      statusText,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }
}
