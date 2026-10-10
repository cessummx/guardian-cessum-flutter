// Version para CELULAR (Android/iOS) del selector de fotos. Usa image_picker.
// Este archivo se compila cuando la app NO corre en web. En el uso actual
// (app web subida a cPanel) el que corre es foto_web_picker_web.dart.
import 'package:image_picker/image_picker.dart';

import 'foto_web_picker.dart';

Future<FotoElegida?> pickFotoImpl() async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 900,
    maxHeight: 900,
    imageQuality: 75,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  return FotoElegida(bytes, x.mimeType ?? 'image/jpeg');
}


Future<DocElegido?> pickDocImpl({String tipo = 'ambos'}) async {
  final f = await pickFotoImpl();
  if (f == null) return null;
  return DocElegido(f.bytes, f.mime, 'documento.jpg');
}
