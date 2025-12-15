import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

class VoxiaModelActionResult {
  const VoxiaModelActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class VoxiaModelManager extends ChangeNotifier {
  VoxiaModelManager({String? defaultModelAssetKey})
    : defaultModelAssetKey =
          defaultModelAssetKey ?? VoxiaModelManager.defaultAssetKey;

  static const String defaultAssetKey = 'assets/models/gemma3-1B-it-int4.task';

  static void initializeGemma() {
    FlutterGemma.initialize();
  }

  final String defaultModelAssetKey;

  bool _isInstalling = false;
  double _progress = 0.0;

  bool get isInstalling => _isInstalling;
  double get progress => _progress;

  Future<VoxiaModelActionResult> installFromFile() async {
    if (!io.Platform.isAndroid) {
      return const VoxiaModelActionResult(
        success: false,
        message: 'Esta operacion solo esta disponible en Android.',
      );
    }

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['task'],
      );

      if (result == null || result.files.isEmpty) {
        return const VoxiaModelActionResult(
          success: false,
          message: 'No se selecciono ningun archivo.',
        );
      }

      final String? pickedPath = result.files.single.path;
      if (pickedPath == null) {
        return const VoxiaModelActionResult(
          success: false,
          message: 'Ruta de archivo invalida.',
        );
      }

      await _installModelFromPath(pickedPath);
      final bool valid = await _validateModelActivation('model.task');
      if (valid) {
        return const VoxiaModelActionResult(
          success: true,
          message: 'Instalacion completada con exito.',
        );
      }
      return const VoxiaModelActionResult(
        success: false,
        message:
            'Instalacion completada pero la activacion del modelo fallo. Revisa los registros o usa la pestaña Modelos.',
      );
    } catch (e) {
      return VoxiaModelActionResult(
        success: false,
        message: 'Error instalando modelo: $e',
      );
    }
  }

  Future<VoxiaModelActionResult> installDefaultModel() async {
    if (!io.Platform.isAndroid) {
      return const VoxiaModelActionResult(
        success: false,
        message: 'Esta operacion solo esta disponible en Android.',
      );
    }

    try {
      await _installModelFromAsset(defaultModelAssetKey);
      final bool valid = await _validateModelActivation(defaultModelAssetKey);
      if (valid) {
        return const VoxiaModelActionResult(
          success: true,
          message: 'Instalacion completada y verificada.',
        );
      }
      return const VoxiaModelActionResult(
        success: false,
        message:
            'Instalacion completada pero la activacion del modelo fallo. Revisa los registros o usa la pestaña Modelos.',
      );
    } catch (e) {
      return VoxiaModelActionResult(
        success: false,
        message: 'Error instalando modelo: $e',
      );
    }
  }

  Future<VoxiaModelActionResult> checkInstalledByKey(String assetKey) async {
    try {
      final bool isInstalled = await _validateModelActivation(assetKey);
      if (isInstalled) {
        return VoxiaModelActionResult(
          success: true,
          message: 'Modelo encontrado para "$assetKey".',
        );
      }
      return VoxiaModelActionResult(
        success: false,
        message:
            'No se encontro instalacion para "$assetKey". Verifica que exista en assets/models.',
      );
    } catch (e) {
      return VoxiaModelActionResult(
        success: false,
        message: 'Error comprobando "$assetKey": $e',
      );
    }
  }

  Future<void> _installModelFromPath(String path) async {
    final io.Directory appDocDir = await getApplicationDocumentsDirectory();
    final io.File targetFile = io.File(
      '${appDocDir.path}${io.Platform.pathSeparator}model.task',
    );
    await io.File(path).copy(targetFile.path);

    _isInstalling = true;
    _progress = 0.0;
    notifyListeners();

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromFile(targetFile.path).withProgress((num progress) {
        _progress = progress.toDouble();
        notifyListeners();
      }).install();
    } finally {
      _isInstalling = false;
      _progress = 0.0;
      notifyListeners();
    }
  }

  Future<void> _installModelFromAsset(String assetKey) async {
    _isInstalling = true;
    _progress = 0.0;
    notifyListeners();

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      ).fromAsset(assetKey).withProgress((num progress) {
        _progress = progress.toDouble();
        notifyListeners();
      }).install();
    } finally {
      _isInstalling = false;
      _progress = 0.0;
      notifyListeners();
    }
  }

  Future<bool> _validateModelActivation(String assetKeyOrPath) async {
    try {
      bool isInstalled = await FlutterGemma.isModelInstalled(assetKeyOrPath);
      if (isInstalled) {
        return true;
      }

      try {
        final String basename =
            assetKeyOrPath.split(io.Platform.pathSeparator).last;
        isInstalled = await FlutterGemma.isModelInstalled(basename);
      } catch (_) {
        isInstalled = false;
      }
      return isInstalled;
    } catch (_) {
      return false;
    }
  }
}
