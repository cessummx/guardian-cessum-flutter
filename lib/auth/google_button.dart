// Exporta la versión correcta del botón de Google según la plataforma.
// En web usa el botón oficial de Google (obligatorio desde la nueva API);
// en móvil usa un botón normal que llama a authenticate().
export 'google_button_io.dart'
    if (dart.library.html) 'google_button_web.dart';
