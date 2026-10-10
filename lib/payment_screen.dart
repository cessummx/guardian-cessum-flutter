import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'generaciones_service.dart';
import 'helpers.dart';
import 'student_profile.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, this.embebido = false});
  /// (4-oct-2026) Dentro de «Pagos» (pestañas) va sin barra propia: la pone el contenedor.
  final bool embebido;


  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Future<_PaymentScreenData> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _cargarDatos();
  }

  /// (8-oct-2026) EL FORMULARIO DEL ALUMNO LO DICE EL GUARDIÁN, NO LA LISTA.
  /// Antes esta pantalla solo cruzaba la generación del perfil con la lista
  /// de generaciones (el JSON de pagosJsonUrl). Cada generación nueva que no
  /// se agregaba ahí salía como «no aparece en la lista activa» —caso real:
  /// Maestría en Educación 26-4, cuyo formulario el Guardián ya tenía
  /// registrado (hoja LinksPago) desde el 22-sep. Ahora se pide primero
  /// mi_pago_mensual (misma llamada que «Lo que debo»), que devuelve linkPago
  /// por programa y generación; la lista queda como respaldo y para «Otras
  /// generaciones». Si la lista no carga pero el Guardián sí respondió, la
  /// pantalla se pinta igual con el formulario del alumno.
  Future<_PaymentScreenData> _cargarDatos() async {
    final perfil = await StudentProfile.load();

    List<GeneracionItem> generaciones = <GeneracionItem>[];
    var listaFallo = false;
    final resultados = await Future.wait<dynamic>([
      GeneracionesService.obtener().catchError((Object _) {
        listaFallo = true;
        return <GeneracionItem>[];
      }),
      perfil == null ? Future<String>.value('') : _linkPagoGuardian(perfil),
    ]);
    generaciones = List<GeneracionItem>.from(resultados[0] as List);
    final linkGuardian = resultados[1] as String;

    String? urlMiGeneracion;
    if (perfil != null) {
      if (linkGuardian.isNotEmpty) {
        urlMiGeneracion = linkGuardian;
      } else {
        for (final g in generaciones) {
          if (_mismaGeneracion(g.nombre, perfil.generacion)) {
            urlMiGeneracion = g.url;
            break;
          }
        }
      }
      // Si el Guardián dio el formulario y la lista no trae esa generación,
      // se agrega al principio para que también aparezca en el listado.
      if (linkGuardian.isNotEmpty &&
          !generaciones.any((g) => _mismaGeneracion(g.nombre, perfil.generacion))) {
        generaciones = [
          GeneracionItem(
              nombre: 'Generación ${perfil.generacion.trim()}',
              url: linkGuardian),
          ...generaciones,
        ];
      }
    }

    // Sin lista Y sin formulario del Guardián no hay nada que mostrar: se
    // deja ver el error con su botón de reintentar, como antes.
    if (listaFallo && urlMiGeneracion == null) {
      throw Exception('No se pudo cargar la lista de generaciones');
    }

    return _PaymentScreenData(
      generaciones: generaciones,
      perfil: perfil,
      urlMiGeneracion: urlMiGeneracion,
    );
  }

  /// El formulario de pago del alumno según el Guardián (linkPago de
  /// mi_pago_mensual: hoja LinksPago, por programa y generación). Vacío si
  /// no hay matrícula, si no respondió o si no tiene enlace registrado.
  Future<String> _linkPagoGuardian(StudentProfile p) async {
    final mat = p.matricula.trim();
    if (mat.isEmpty) return '';
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mi_pago_mensual',
        'matricula': mat,
        'programa': p.programa,
        'generacion': p.generacion,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 25));
      final d = jsonDecode(r.body);
      if (d is Map && d['ok'] == true) {
        final link = (d['linkPago'] ?? '').toString().trim();
        if (link.startsWith('http')) return link;
      }
    } catch (_) {
      // Sin respuesta: se cae a la lista, como siempre.
    }
    return '';
  }

  Future<void> _recargar() async {
    // Si la lista no carga, la recarga sigue: _cargarDatos ya sabe caer al
    // formulario que da el Guardián.
    try { await GeneracionesService.obtener(forzarRecarga: true); } catch (_) {}
    if (mounted) setState(() {
      _futureData = _cargarDatos();
    });
  }

  void _volverAlMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: widget.embebido ? null : AppBar(
        title: const Text(
          'Registrar un pago',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Inicio',
            onPressed: _volverAlMenu,
          ),
        ],
      ),
      body: FutureBuilder<_PaymentScreenData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: cessumRed),
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(onReintentar: _recargar);
          }

          final data = snapshot.data;
          if (data == null) {
            return _ErrorView(onReintentar: _recargar);
          }

          return RefreshIndicator(
            color: cessumRed,
            onRefresh: _recargar,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // (ago-8) QUÉ VAS A PAGAR. Antes esta pantalla solo llevaba al
                // formulario de colegiatura, y la reinscripción vivía escondida
                // en Trámites — nadie la encontraba. Aquí quedan las dos cosas
                // separadas y explicadas: son pagos distintos, con formularios
                // distintos, y el alumno tiene que saber cuál le toca.
                const _QuePagar(),
                const SizedBox(height: 16),
                if (data.perfil != null && data.urlMiGeneracion != null) ...[
                  _MiGeneracionCard(
                    perfil: data.perfil!,
                    url: data.urlMiGeneracion!,
                  ),
                  const SizedBox(height: 16),
                  _ReinscripcionCard(perfil: data.perfil),
                  const SizedBox(height: 24),
                  const _SeparadorOtras(),
                  const SizedBox(height: 12),
                ] else if (data.perfil != null &&
                    data.urlMiGeneracion == null) ...[
                  _AvisoPerfilSinCoincidencia(
                    generacionPerfil: data.perfil!.generacion,
                  ),
                  const SizedBox(height: 16),
                  _ReinscripcionCard(perfil: data.perfil),
                  const SizedBox(height: 20),
                ] else ...[
                  _ReinscripcionCard(perfil: data.perfil),
                  const SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Selecciona tu generacion para abrir el formulario de pago correspondiente:',
                      style: TextStyle(fontSize: 14, color: cessumMuted(context)),
                    ),
                  ),
                ],

                // Lista completa de generaciones
                ...data.generaciones.map((g) {
                  final esMia = data.perfil != null &&
                      _mismaGeneracion(g.nombre, data.perfil!.generacion);
                  return Card(
                    color: Theme.of(context).cardColor,
                    elevation: esMia ? 0 : 1,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: esMia
                          ? const BorderSide(color: cessumGold, width: 1.5)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: esMia ? cessumGold : Colors.grey.shade300,
                        child: Icon(
                          Icons.school,
                          color: esMia ? Colors.white : Colors.grey.shade700,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        g.nombre,
                        style: TextStyle(
                          fontWeight: esMia ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.open_in_new,
                        color: cessumGold,
                        size: 18,
                      ),
                      onTap: () => Helpers.abrirUrlExterna(g.url, context),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PaymentScreenData {
  final List<GeneracionItem> generaciones;
  final StudentProfile? perfil;
  final String? urlMiGeneracion;

  _PaymentScreenData({
    required this.generaciones,
    required this.perfil,
    required this.urlMiGeneracion,
  });
}

// Tarjeta grande con la generacion del alumno y boton directo
class _MiGeneracionCard extends StatelessWidget {
  final StudentProfile perfil;
  final String url;

  const _MiGeneracionCard({required this.perfil, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cessumRed, cessumRed.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: cessumRed.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.school, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'TU GENERACION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            perfil.generacion,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            perfil.programa,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cessumRed,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () => Helpers.abrirUrlExterna(url, context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text(
                'Ir a mi formulario de pago',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado que separa los dos pagos que el alumno puede hacer. Sin esto,
/// "Registrar un pago" parecía tener una sola opción y la reinscripción se
/// buscaba en Trámites, donde nadie la encontraba.
class _QuePagar extends StatelessWidget {
  const _QuePagar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: cessumRed),
              SizedBox(width: 6),
              Text('¿QUÉ VAS A PAGAR?',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: cessumRed)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Son dos pagos distintos y cada uno tiene su propio formulario:',
            style: TextStyle(fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 6),
          const Text(
            '•  Colegiatura o materia: tu pago del periodo.\n'
            '•  Reinscripción: la cuota para continuar al siguiente bloque '
            'de asignaturas.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Acceso a la reinscripción desde donde el alumno lo busca: Pagos.
/// Sigue existiendo en Trámites; esto no lo quita, lo pone también aquí.
class _ReinscripcionCard extends StatelessWidget {
  final StudentProfile? perfil;
  const _ReinscripcionCard({this.perfil});

  /// (ago-9) ¿A ESTE ALUMNO le toca reinscripción? Antes la tarjeta explicaba
  /// la regla general y lo dejaba deducir si aplicaba a su caso — que es
  /// justo lo que un alumno no tiene por qué saber. La reinscripción es una
  /// cuota de la modalidad NO ESCOLARIZADA; en Mixta la inscripción se cubre
  /// al inicio del periodo y no hay reinscripciones intermedias.
  bool? get _leToca {
    if (_esLicenciatura) return true; // (8-oct-2026) licenciatura: cada cuatrimestre, sea cual sea su modalidad
    final m = (perfil?.modalidad ?? '').toLowerCase();
    if (m.isEmpty) return null; // sin dato: no se afirma nada
    if (m.contains('mixt')) return false;
    if (m.contains('escolarizada') || m.contains('linea') ||
        m.contains('línea')) {
      return true;
    }
    return null;
  }

  /// (8-oct-2026) CADA CUÁNTO SE PAGA, SEGÚN EL PROGRAMA. Antes decía «cada
  /// cuatro asignaturas» para todos: en la Maestría en Educación es cada
  /// tres, en los demás posgrados cada cuatro y en licenciatura cada
  /// cuatrimestre.
  bool get _esLicenciatura =>
      (perfil?.programa ?? '').toLowerCase().contains('licenciatura');
  bool get _esMaestriaEducacion {
    final p = (perfil?.programa ?? '').toLowerCase();
    return p.contains('maestr') && p.contains('educaci') && !p.contains('inclusiv');
  }
  String get _cadaCuanto => _esLicenciatura
      ? 'una cuota cada cuatrimestre'
      : _esMaestriaEducacion
          ? 'una cuota cada tres asignaturas'
          : 'una cuota cada cuatro asignaturas';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.refresh, color: cessumGold, size: 22),
              SizedBox(width: 8),
              Text('REINSCRIPCIÓN',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: cessumGold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Cuota para continuar al siguiente bloque de asignaturas.',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_leToca == true) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0A800).withValues(alpha: 0.12), // (24-sep) modo oscuro
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
              ),
              child: Text(
                  _esLicenciatura
                      ? '✔ En la licenciatura SÍ se paga reinscripción: $_cadaCuanto.'
                      : '✔ En tu modalidad (${perfil!.modalidad}) SÍ se paga '
                          'reinscripción: $_cadaCuanto.',
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            const Text(
              'El monto exacto y cuántas llevas pagadas los ves en '
              'Pagos → Cuánto debo.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ] else if (_leToca == false) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E3E).withValues(alpha: 0.09), // (24-sep) modo oscuro
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.35)),
              ),
              child: Text(
                  'En tu modalidad (${perfil!.modalidad}) NO se paga '
                  'reinscripción: tu inscripción se cubre al inicio del '
                  'periodo. Deja este botón para quien lo necesite.',
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
          ] else ...[
            const Text(
              'Aplica en modalidad no escolarizada: cada tres asignaturas en la '
              'Maestría en Educación y cada cuatro en los demás posgrados; en '
              'licenciatura, cada cuatrimestre. Si tienes duda de si te toca, '
              'revísalo en Pagos → Cuánto debo o pregunta en Vicerrectoría antes de pagar.',
              style: TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () =>
                  Helpers.abrirUrlExterna(formReinscripcionUrl, context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text(
                'Ir al formulario de reinscripción',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Aviso cuando el alumno tiene generacion configurada pero no esta en la lista actual
class _AvisoPerfilSinCoincidencia extends StatelessWidget {
  final String generacionPerfil;

  const _AvisoPerfilSinCoincidencia({required this.generacionPerfil});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: cessumGold, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No encontramos tu formulario',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tu generación ($generacionPerfil) todavía no tiene formulario de pago registrado. '
                  'Escríbenos a Atención a Estudiantes para que te lo compartamos; '
                  'mientras, no uses el de otra generación.',
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeparadorOtras extends StatelessWidget {
  const _SeparadorOtras();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Otras generaciones',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onReintentar;

  const _ErrorView({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: cessumRed),
            const SizedBox(height: 16),
            const Text(
              'No se pudo cargar la lista de pagos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa tu conexion a internet e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: onReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}


// Compara dos generaciones ignorando la palabra "Generacion" y los espacios,
// para que "Generacion 24-2" coincida con "24-2".
String _soloCodigoGen(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll('generación', '').replaceAll('generacion', '');
  t = t.replaceAll(' ', '').trim();
  return t;
}

bool _mismaGeneracion(String a, String b) {
  final ca = _soloCodigoGen(a);
  final cb = _soloCodigoGen(b);
  return ca.isNotEmpty && ca == cb;
}
