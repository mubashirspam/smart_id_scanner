import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerWidget extends StatelessWidget {
  final Widget child;
  final VoidCallback onPermissionDenied;
  
  const PermissionHandlerWidget({
    super.key,
    required this.child,
    required this.onPermissionDenied,
  });
  
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PermissionStatus>(
      future: Permission.camera.status,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (snapshot.data!.isGranted) {
            return child;
          } else {
            return _buildPermissionDeniedWidget(context);
          }
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
  
  Widget _buildPermissionDeniedWidget(BuildContext context) {
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
            const Text(
              'This app needs camera access to scan documents.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                final status = await Permission.camera.request();
                if (status.isPermanentlyDenied) {
                  openAppSettings();
                } else if (!status.isGranted) {
                  onPermissionDenied();
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}