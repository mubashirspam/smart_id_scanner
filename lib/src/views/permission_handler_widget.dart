import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback onPermissionDenied;

  const PermissionHandlerWidget({
    super.key,
    required this.child,
    required this.onPermissionDenied,
  });

  @override
  State<PermissionHandlerWidget> createState() =>
      _PermissionHandlerWidgetState();
}

class _PermissionHandlerWidgetState extends State<PermissionHandlerWidget>
    with WidgetsBindingObserver {
  PermissionStatus? _permissionStatus;
  bool _isChecking = true;
  bool _hasRequestedPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-check permission when app comes back to foreground
    // This handles the case where user grants permission in Settings
    if (state == AppLifecycleState.resumed && _hasRequestedPermission) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (mounted) {
      setState(() {
        _permissionStatus = status;
        _isChecking = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isChecking = true;
      _hasRequestedPermission = true;
    });

    try {
      final status = await Permission.camera.request();
      
      if (mounted) {
        setState(() {
          _permissionStatus = status;
          _isChecking = false;
        });

        if (!status.isGranted && !status.isPermanentlyDenied) {
          widget.onPermissionDenied();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
        widget.onPermissionDenied();
      }
    }
  }

  Future<void> _openSettings() async {
    setState(() {
      _isChecking = true;
    });

    final opened = await openAppSettings();
    
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
      
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open settings. Please open Settings app manually.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionStatus?.isGranted == true) {
      return widget.child;
    }

    return _buildPermissionDeniedWidget(context);
  }

  Widget _buildPermissionDeniedWidget(BuildContext context) {
    final isPermanentlyDenied = _permissionStatus?.isPermanentlyDenied == true;
    final isFirstTime = _permissionStatus?.isDenied == true && !isPermanentlyDenied;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 24),
            const Text(
              'Camera Permission Required',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isPermanentlyDenied
                  ? 'Camera access was denied. Please enable it in Settings to scan documents.'
                  : 'This app needs camera access to scan documents.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            if (isPermanentlyDenied) ...[
              ElevatedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
                label: Text(Platform.isIOS ? 'Open Settings' : 'Grant Permission'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _checkPermission,
                child: const Text('I\'ve enabled it'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Allow Camera Access'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
            if (Platform.isIOS && !isPermanentlyDenied) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(height: 8),
                    Text(
                      'iOS Tip: If the permission dialog doesn\'t appear, try closing and reopening the app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}