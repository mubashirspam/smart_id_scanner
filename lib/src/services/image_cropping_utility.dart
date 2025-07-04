import 'dart:io';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageCroppingUtility {
  static Future<File> cropImageToAspectRatio(
    File imageFile,
    double targetAspectRatio,
  ) async {
    try {
      print('=== CROPPING DEBUG START ===');
      print('Original file path: ${imageFile.path}');
      print('Original file exists: ${await imageFile.exists()}');
      
      if (!await imageFile.exists()) {
        print('ERROR: Original file does not exist');
        return imageFile;
      }
      
      // Read the image
      final bytes = await imageFile.readAsBytes();
      print('Read ${bytes.length} bytes from original file');
      
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        print('ERROR: Failed to decode image');
        return imageFile; // Return original if decoding fails
      }
      
      print('Image dimensions: ${image.width} x ${image.height}');
      
      // Calculate current aspect ratio
      final currentAspectRatio = image.width / image.height;
      print('Current aspect ratio: $currentAspectRatio, Target: $targetAspectRatio');
      
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
        print('Image already at target aspect ratio');
        return imageFile;
      }
      
      print('New dimensions: $newWidth x $newHeight');
      
      // Calculate crop position (center crop)
      final x = (image.width - newWidth) ~/ 2;
      final y = (image.height - newHeight) ~/ 2;
      
      print('Crop position: x=$x, y=$y');
      
      // Crop the image
      final croppedImage = img.copyCrop(
        image,
        x: x,
        y: y,
        width: newWidth,
        height: newHeight,
      );
      
      // Save the cropped image to a reliable location
      final croppedBytes = img.encodeJpg(croppedImage, quality: 95);
      print('Encoded cropped image: ${croppedBytes.length} bytes');
      
      // Use app documents directory for more reliable storage
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'cropped_${timestamp}.jpg';
      final croppedFile = File('${appDir.path}/$filename');
      
      print('Writing cropped file to: ${croppedFile.path}');
      
      // Write the cropped file
      await croppedFile.writeAsBytes(croppedBytes);
      
      // Verify the file was written successfully
      if (await croppedFile.exists()) {
        final writtenSize = await croppedFile.length();
        print('Cropped file written successfully: $writtenSize bytes');
        
        // Only delete original after confirming cropped file exists
        try {
          await imageFile.delete();
          print('Original file deleted');
        } catch (e) {
          print('Warning: Could not delete original file: $e');
          // Continue anyway, the cropped file is what matters
        }
        
        print('=== CROPPING DEBUG END ===');
        return croppedFile;
      } else {
        print('ERROR: Cropped file was not created successfully');
        return imageFile; // Return original if cropped file creation failed
      }
      
    } catch (e, stackTrace) {
      print('Error cropping image: $e');
      print('Stack trace: $stackTrace');
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