// Selector de foto que funciona tanto en web como en celular.
// En web usa el selector propio del navegador (foto_web_picker_web.dart);
// en celular usa image_picker (foto_web_picker_stub.dart). Flutter elige
// automaticamente la version correcta al compilar.
import 'foto_web_picker_stub.dart'
    if (dart.library.html) 'foto_web_picker_web.dart';

/// Foto ya elegida y reducida: sus bytes y su tipo (ej. image/jpeg).
class FotoElegida {
  final List<int> bytes;
  final String mime;
  const FotoElegida(this.bytes, this.mime);
}

/// Abre el selector de fotos y devuelve la foto ya reducida de tamano.
/// Devuelve null si el usuario cancela.
Future<FotoElegida?> seleccionarFoto() => pickFotoImpl();


/// Documento elegido (imagen o PDF): bytes, tipo y nombre del archivo.
class DocElegido {
  final List<int> bytes;
  final String mime;
  final String nombre;
  const DocElegido(this.bytes, this.mime, this.nombre);
}

/// Abre el selector aceptando imagen o PDF. Las imagenes se reducen;
/// los PDF se aceptan hasta 8 MB. Devuelve null si el usuario cancela.
///   tipo = 'imagen' -> solo imagenes (en celular abre Galeria/Camara directo)
///   tipo = 'pdf'    -> solo PDF (abre Archivos)
///   tipo = 'ambos'  -> imagen o PDF
Future<DocElegido?> seleccionarDocumento({String tipo = 'ambos'}) =>
    pickDocImpl(tipo: tipo);
