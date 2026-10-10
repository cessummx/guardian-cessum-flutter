import 'package:flutter/material.dart';

// =====================================================
// COLORES OFICIALES CESSUM
// =====================================================
const Color cessumRed = Color(0xFFC8202F);
const Color cessumGold = Color(0xFFB8842C);

// =====================================================
// AULA VIRTUAL (Moodle)
// =====================================================
const String moodleUrl = 'https://aula.cessum.mx';
const String moodleDomain = 'aula.cessum.mx';

// =====================================================
// CONTROL DE VERSIONES
// =====================================================
const String versionCheckUrl = 'https://www.cessum.mx/app/version.json';

// =====================================================
// PAGOS - GIST DINAMICO (editable sin tocar la app)
// =====================================================
const String pagosJsonUrl =
    'https://gist.githubusercontent.com/cessummx/c5dc2be477be535ee92bc5d865f2ae7c/raw/pagos.json';

// =====================================================
// CARTAS DESCRIPTIVAS - HOSPEDADO EN CPANEL (editable sin tocar la app)
// El archivo cartas.json se sube por File Manager a la MISMA carpeta donde
// vive la app y el version.json (la carpeta del dominio app.cessum.mx,
// junto a index.html y main.dart.js).
// URL publica: https://app.cessum.mx/cartas.json
// Para actualizar las cartas en el futuro: solo reemplazar ese archivo en cPanel,
// sin recompilar la app.
// =====================================================
const String cartasJsonUrl =
    'https://app.cessum.mx/cartas.json';

// =====================================================
// ALUMNOS / DOCENTES - HOSPEDADO EN CPANEL (editable sin tocar la app)
// El archivo alumnos.json se sube por File Manager a la MISMA carpeta donde
// vive la app (la del dominio app.cessum.mx, junto a index.html y cartas.json).
// Contiene la lista de profesores, alumnos activos (con sus datos) y bajas.
// URL publica: https://app.cessum.mx/alumnos.json
// Para actualizar la lista en el futuro: solo reemplazar ese archivo en cPanel,
// sin recompilar la app.
// =====================================================
// PADRON EN VIVO (Opcion A): la app lee el padron directamente del Guardian,
// que entrega alumnos.json ya con las altas/bajas/correcciones aplicadas.
// Asi NO hay que regenerar el archivo estatico nunca mas.
const String alumnosJsonUrl =
    'https://app.cessum.mx/guardian.php?accion=alumnos_json';

// Correo donde llegan las solicitudes de alumnos que no estan en la lista
const String correoSolicitudesAlumno = 'soporte@cessum.mx';

// =====================================================
// SERVICIOS - FORMULARIOS GOOGLE
// =====================================================
const String formServiciosUrl = 'https://forms.gle/C1wRJ8eqBcQryqaD8';
const String formJustificacionUrl = 'https://forms.gle/BkwgrnUhfiyPrELCA';
const String formReinscripcionUrl = 'https://forms.gle/iR68LDFG92dqsHqRA';
const String formCredencialUrl = 'https://forms.gle/8c1UuhbvzVei3JPK9';

// =====================================================
// RECURSOS EXTERNOS
// =====================================================
const String titulacionUrl =
    'https://drive.google.com/file/d/1Y9-Ws3jo-sCQIBqwhXaLSLGUim_Y2hVF/view';
const String convocatoriasUrl = 'https://www.cessum.mx/admisiones';
const String calendarioUrl = 'https://calendar.google.com';
const String sitioWebUrl = 'https://www.cessum.mx';
const String avisoPrivacidadUrl = 'https://www.cessum.mx/aviso-de-privacidad';
const String perfilMoodleUrl = 'https://aula.cessum.mx/user/profile.php';

// =====================================================
// CONTACTO - ALUMNOS ACTUALES
// =====================================================
const String whatsappNumero = '5216421305193';
const String whatsappMensaje = 'Hola, soy alumno de CESSUM y necesito apoyo.';
const String correoFacturacion = 'contacto@cessum.mx';
const String correoInstitucional = 'contacto@cessum.mx';

// =====================================================
// CONTACTO - ADMISIONES (NUEVOS ALUMNOS)
// =====================================================
const String telefonoAdmisiones = '+5216421376117';
const String telefonoAdmisionesFormateado = '+52 1 642 137 6117';
const String whatsappAdmisionesNumero = '5216421376117';
const String whatsappAdmisionesMensaje =
    'Hola, me interesa conocer la oferta educativa de CESSUM.';

// =====================================================
// DATOS BANCARIOS PARA PAGO
// =====================================================
const String bancoNombre = 'BBVA';
const String bancoBeneficiario = 'CESSUM';
const String bancoCuenta = '0120887013';
const String bancoClabe = '012777001208870132';
const String bancoConceptoSugerido = 'Colegiatura + Nombre del alumno';

// =====================================================
// DOMICILIO INSTITUCIONAL
// =====================================================
const String domicilioCalle = 'Capohuiza 1712';
const String domicilioColonia = 'Col. Beltrones';
const String domicilioCiudad = 'Navojoa, Sonora';
const String domicilioCP = 'C.P. 85860';
const String domicilioPais = 'Mexico';
const String razonSocialCompleta = 'Centro de Estudios Superiores del Mayo, A.C.';

// =====================================================
// CONFIGURACION DE MATRICULA
// =====================================================
const int matriculaLongitud = 8;

// =====================================================
// MODALIDADES DE ESTUDIO
// =====================================================
const List<String> modalidadesEstudio = [
  'No escolarizada',
  'Mixta',
];

// =====================================================
// OFERTA ACADEMICA
// =====================================================
class Programa {
  final String nombre;
  final String url;
  final String nivel;

  const Programa({
    required this.nombre,
    required this.url,
    required this.nivel,
  });
}

const List<Programa> programasAcademicos = [
  // (15-sep-2026) Licenciatura en Pedagogía, RVOE 2026DGES-09. Faltaba en
  // esta lista, así que no aparecía al crear una asignación ni al dar de alta
  // un alumno. El nombre va EXACTAMENTE como en el backend, con acento: si
  // difiere en un carácter se crea una variante fantasma que parte el grupo
  // en dos, como pasó en julio con los programas sin acentos.
  Programa(
    nombre: 'Licenciatura en Pedagogía',
    url: 'https://www.cessum.mx/licenciatura-en-pedagogia',
    nivel: 'Licenciatura',
  ),
  Programa(
    nombre: 'Maestría en Educación Inclusiva',
    url: 'https://www.cessum.mx/maestria-en-educacion-inclusiva',
    nivel: 'Maestria',
  ),
  Programa(
    nombre: 'Maestría en Educación',
    url: 'https://www.cessum.mx/maestria-en-educacion',
    nivel: 'Maestria',
  ),
  Programa(
    nombre: 'Maestría en Pedagogía',
    url: 'https://www.cessum.mx/maestria-en-pedagogia',
    nivel: 'Maestria',
  ),
  Programa(
    nombre: 'Maestría en Psicopedagogía',
    url: 'https://www.cessum.mx/maestria-en-psicopedagogia',
    nivel: 'Maestria',
  ),
  Programa(
    nombre: 'Doctorado en Educación con Énfasis en Investigación',
    url: 'https://www.cessum.mx/doctorado-en-educacion',
    nivel: 'Doctorado',
  ),
  Programa(
    nombre: 'Doctorado en Ciencias de la Educación',
    url: 'https://www.cessum.mx/doctorado-ciencias-educacion',
    nivel: 'Doctorado',
  ),
];
