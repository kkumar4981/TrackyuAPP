import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api.dart';

Future<String?> capturePunchSelfie() => captureCameraPhoto(front: true);
Future<String?> captureVisitPhoto() => captureCameraPhoto(front: false);
Future<String?> captureCameraPhoto({required bool front}) async {
  var permission = await Permission.camera.status;
  if (permission.isPermanentlyDenied || permission.isRestricted) {
    throw ApiFailure(
      'CAMERA_PERMISSION',
      front
          ? 'Allow camera access in app settings to take your attendance selfie.'
          : 'Allow camera access in app settings to take a visit photo.',
    );
  }
  if (!permission.isGranted) permission = await Permission.camera.request();
  if (!permission.isGranted) {
    throw ApiFailure(
      'CAMERA_PERMISSION',
      front
          ? 'Camera access is required for the punch-in selfie.'
          : 'Camera access is required for a visit photo.',
    );
  }
  XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: front ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 2097152) {
      throw const ApiFailure(
        'SELFIE_TOO_LARGE',
        'Retake the photo. The image must be no larger than 2 MB.',
      );
    }
    return base64Encode(bytes);
  } on ApiFailure {
    rethrow;
  } catch (_) {
    throw const ApiFailure(
      'CAMERA_UNAVAILABLE',
      'Unable to open the camera. Check camera permission and try again.',
    );
  } finally {
    if (file != null) {
      try {
        final temp =
            (await getTemporaryDirectory()).absolute.path +
            Platform.pathSeparator;
        final path = File(file.path).absolute.path;
        if (path.startsWith(temp) && await File(path).exists()) {
          await File(path).delete();
        }
      } catch (_) {
        /* Never delete outside app-private temporary storage. */
      }
    }
  }
}
