import 'roles_service.dart';

// =====================================================
// CONFIGURACION DE ADMINISTRADORES
// =====================================================
// Correos institucionales con permiso de "Vista de administrador".
// Estos correos pueden previsualizar la app como la ven los estudiantes
// y los docentes, sin necesidad de tener matricula ni estar en alumnos.json.
//
// Para AGREGAR un administrador en el futuro: solo escribe su correo aqui
// abajo (todo en minusculas) separado por comas. No hay que tocar nada mas.
// =====================================================
const List<String> adminEmails = [
  'contacto@cessum.mx',
  'soporte@cessum.mx',
  'vicerrectoria@cessum.mx',
];

/// Devuelve true si el correo (normalmente el de la sesion de Google) es de
/// un administrador. Compara sin distinguir mayusculas/minusculas ni espacios.
/// Además de la lista fija de arriba (que siempre vale), reconoce a quienes
/// tengan un rol de administración asignado desde la app (RolesService).
bool esAdmin(String? correo) {
  if (correo == null) return false;
  final c = correo.trim().toLowerCase();
  if (adminEmails.contains(c)) return true;
  final rolDin = RolesService.rolDinamico(c);
  // Cualquier rol de administración cuenta; 'docente' NO entra al panel admin.
  if (rolDin != null && rolDin.isNotEmpty && rolDin != 'docente') return true;
  return false;
}


// =====================================================
// ROLES DE ADMINISTRACION
// =====================================================
// 'total'   : ve todo el panel (Vicerrectoria).
// 'soporte' : Mesa de ayuda, avisos y registro de accesos.
// 'control' : tramites, documentos, pagos, credenciales, ficha, etc.
// Para asignar un rol, agregue el correo al mapa; quien no aparezca
// y sea administrador, tendra rol 'total'.
const Map<String, String> rolPorCorreo = {
  'vicerrectoria@cessum.mx': 'total',
  'contacto@cessum.mx': 'total',
  'soporte@cessum.mx': 'total', // cambie a 'soporte' cuando delegue
};

String rolDe(String? correo) {
  if (correo == null) return 'total';
  final c = correo.trim().toLowerCase();
  if (rolPorCorreo.containsKey(c)) return rolPorCorreo[c]!;
  final rolDin = RolesService.rolDinamico(c);
  if (rolDin != null && rolDin.isNotEmpty && rolDin != 'docente') {
    return rolDin;
  }
  return 'total';
}

const Map<String, Set<String>> seccionesPorRol = {
  'total': {},
  'soporte': {'incidencias', 'avisos', 'accesos'},
  'control': {
    'tramites', 'justificaciones', 'bajas', 'pagos', 'seguimientoPagos',
    'solicitudesCorreccion', 'credenciales', 'ficha', 'documentos',
    'incidencias', 'avisos'
  },
  // (ago-2026) Rol para Coordinación Académica (observaciones, ranking,
  // adaptaciones, convenios): sin acceso a pagos, bajas ni credenciales.
  // Antes este rol no estaba definido y veía TODO por el default.
  'academico': {
    'academico', 'documentos', 'justificaciones', 'incidencias',
    'avisos', 'ficha'
  },
};

/// true si el rol puede ver la seccion. El rol 'total' ve todo.
bool rolPermite(String rol, String seccion) {
  if (rol == 'total') return true;
  final s = seccionesPorRol[rol];
  if (s == null) return true;
  return s.contains(seccion);
}
