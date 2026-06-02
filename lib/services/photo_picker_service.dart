import 'dart:io';

import 'package:image_picker/image_picker.dart';

class PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickFromGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return File(picked.path);
  }

  /// 用相機拍一張照片（日常照護任務完成證明用）。
  /// 使用者取消回 null（呼叫端不可 crash）。
  Future<File?> pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked == null) return null;
    return File(picked.path);
  }
}
