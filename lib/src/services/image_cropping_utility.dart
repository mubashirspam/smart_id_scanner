import 'dart:io';
import 'dart:ui';
import 'package:image/image.dart' as img;

class ImageCroppingUtility {
  static Future<File> cropImageToAspectRatio(
    File imageFile,
    double targetAspectRatio,
  ) async {
    try {
      // Read the image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return imageFile; // Return original if decoding fails
      }
      
      // Calculate current aspect ratio
      final currentAspectRatio = image.width / image.height;
      
      // Determine new dimensions
      int newWidth = image.width;
      int newHeight = image.height;
      
      if (currentAspectRatio > targetAspectRatio) {
        // Image is wider than target - crop width
        newWidth = (image.height * targetAspectRatio).round();
      } else if (currentAspectRatio < targetAspectRatio) {
        // Image is taller than target - crop height
        newHeight = (image.width / targetAspectRatio).round();
      } else {
        // Already at target aspect ratio
        return imageFile;
      }
      
      // Calculate crop position (center crop)
      final x = (image.width - newWidth) ~/ 2;
      final y = (image.height - newHeight) ~/ 2;
      
      // Crop the image
      final croppedImage = img.copyCrop(
        image,
        x: x,
        y: y,
        width: newWidth,
        height: newHeight,
      );
      
      // Save the cropped image
      final croppedBytes = img.encodeJpg(croppedImage, quality: 95);
      
      // Create a new file with cropped prefix
      final directory = imageFile.parent;
      final filename = imageFile.uri.pathSegments.last;
      final croppedFile = File('${directory.path}/cropped_$filename');
      
      await croppedFile.writeAsBytes(croppedBytes);
      
      // Delete the original file to save space
      try {
        await imageFile.delete();
      } catch (_) {}
      
      return croppedFile;
    } catch (e) {
      print('Error cropping image: $e');
      return imageFile; // Return original on error
    }
  }
  
  static Rect calculateCropRect(
    double imageWidth,
    double imageHeight,
    double targetAspectRatio,
  ) {
    final currentAspectRatio = imageWidth / imageHeight;
    
    double cropWidth = imageWidth;
    double cropHeight = imageHeight;
    
    if (currentAspectRatio > targetAspectRatio) {
      // Image is wider than target - crop width
      cropWidth = imageHeight * targetAspectRatio;
    } else if (currentAspectRatio < targetAspectRatio) {
      // Image is taller than target - crop height
      cropHeight = imageWidth / targetAspectRatio;
    }
    
    // Calculate center position
    final x = (imageWidth - cropWidth) / 2;
    final y = (imageHeight - cropHeight) / 2;
    
    return Rect.fromLTWH(x, y, cropWidth, cropHeight);
  }
}