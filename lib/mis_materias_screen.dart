import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'solicitar_correccion_screen.dart';

/// Pantalla de SOLO CONSULTA: el docente ve las materias que tiene asignadas
/// (programa, generación, grupo, fechas de vigencia). No captura nada aquí;
/// es informativa y está SIEMPRE disponible, aunque la captura esté cerrada.
class MisMateriasScreen extends StatefulWidget {
  const MisMateriasScreen({super.key});

  @override
  State<MisMateriasScreen> createState() => _MisMateriasScreenState();
}

class _MateriaAsignada {
  final String programa;
  final String generacion;
  final String grupo;
  final String tipoSesiones;
  final String dia;
  final String hora;
  final String materia;
  final String clave;
  final String ciclo;
  final String inicio;
  final String termino;
  final String linkLlamada;
  final String linkAula;
  const _MateriaAsignada({
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.tipoSesiones,
    required this.dia,
    required this.hora,
    required this.materia,
    required this.clave,
    required this.ciclo,
    required this.inicio,
    required this.termino,
    required this.linkLlamada,
    required this.linkAula,
  });
}

// Convierte una fecha a algo legible en espanol: "25 may 2026".
// Entiende dos formatos:
//   1) ISO corta:  "2026-05-25"
//   2) Texto largo en ingles (que manda el Guardian/JS):
//      "Mon May 25 2026 00:00:00 GMT-0700 (Pacific Daylight Time)"
// Si no la reconoce, devuelve el texto original.
String _fechaBonita(String s) {
  if (s.trim().isEmpty) return '';
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  const mesesIngles = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };

  // --- Formato 1: ISO corta "2026-05-25" ---
  final base = s.length >= 10 ? s.substring(0, 10) : s;
  final partesIso = base.split('-');
  if (partesIso.length == 3) {
    final anio = int.tryParse(partesIso[0]);
    final mes = int.tryParse(partesIso[1]);
    final dia = int.tryParse(partesIso[2]);
    if (anio != null && mes != null && dia != null &&
        mes >= 1 && mes <= 12 && anio > 1900) {
      return '$dia ${meses[mes - 1]} $anio';
    }
  }

  // --- Formato 2: texto largo en ingles ---
  // Ej: "Mon May 25 2026 00:00:00 GMT-0700 (Pacific Daylight Time)"
  // Buscamos el nombre del mes en ingles, el dia y el anio.
  final lower = s.toLowerCase();
  for (final entry in mesesIngles.entries) {
    final idx = lower.indexOf(entry.key);
    if (idx >= 0) {
      // Despues del mes viene el dia; el anio es el primer numero de 4 digitos.
      final resto = s.substring(idx + 3);
      final numeros = RegExp(r'\d+').allMatches(resto).map((m) => m.group(0)!).toList();
      int? dia;
      int? anio;
      for (final n in numeros) {
        if (n.length == 4 && anio == null) {
          anio = int.tryParse(n);
        } else if (dia == null && int.tryParse(n) != null && int.parse(n) >= 1 && int.parse(n) <= 31) {
          dia = int.tryParse(n);
        }
        if (dia != null && anio != null) break;
      }
      if (dia != null && anio != null) {
        return '$dia ${meses[entry.value - 1]} $anio';
      }
    }
  }

  return s;
}

class _MisMateriasScreenState extends State<MisMateriasScreen> {
  List<_MateriaAsignada> _materias = [];
  bool _cargando = true;
  String? _error;

  // Buscador y filtro de estado.
  final TextEditingController _busqueda = TextEditingController();
  String _filtroEstado = 'Todas'; // Todas | En curso | Próximas | Terminadas

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);
  Color get _borde => cessumIsDark(context) ? Colors.white12 : cessumMuted(context).withValues(alpha: 0.18);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Correo con el que realmente se consultó y si venía de una suplantación
  // ("Ver como..."). Sin esto, una sesión vencida o una suplantación activa
  // se veían igual que "no tienes materias".
  String _correoUsado = '';
  bool _suplantando = false;

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.validEmail();
      _correoUsado = correo ?? '';
      _suplantando = SessionStore.impersonation.value != null &&
          SessionStore.impersonation.value!.isNotEmpty;
      if (_correoUsado.isEmpty) {
        if (mounted) {
          setState(() {
            _cargando = false;
            _error =
                'Tu sesión expiró. Vuelve a iniciar sesión para ver tus materias.';
          });
        }
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos',
        'correo': correo ?? '',
      });
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['grupos'] as List<dynamic>? ?? []);
      final mats = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _MateriaAsignada(
          programa: (m['programa'] ?? '').toString(),
          generacion: (m['generacion'] ?? '').toString(),
          grupo: (m['grupo'] ?? '').toString(),
          tipoSesiones: (m['tipoSesiones'] ?? m['modalidad'] ?? '').toString(),
          dia: (m['dia'] ?? '').toString(),
          hora: (m['hora'] ?? '').toString(),
          materia: (m['materia'] ?? '').toString(),
          clave: (m['clave'] ?? '').toString(),
          ciclo: (m['ciclo'] ?? '').toString(),
          inicio: (m['inicio'] ?? '').toString(),
          termino: (m['termino'] ?? '').toString(),
          linkLlamada: (m['linkLlamada'] ?? '').toString(),
          linkAula: (m['linkAula'] ?? '').toString(),
        );
      }).toList();
      // Orden: en curso arriba, luego próximas, y terminadas abajo
      // (las más antiguas al final).
      mats.sort((a, b) {
        final ca = _categoria(a), cb = _categoria(b);
        if (ca != cb) return ca.compareTo(cb);
        final fa = _fechaParse(a.inicio) ?? DateTime(1900);
        final fb = _fechaParse(b.inicio) ?? DateTime(1900);
        return fb.compareTo(fa);
      });
      if (mounted) {
        setState(() {
          _materias = mats;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error =
              'No se pudieron cargar tus materias. Revisa tu conexión e intenta de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis materias'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _materias.isEmpty
                  ? _vistaVacia()
                  : _vistaLista(),
    );
  }

  Widget _vistaLista() {
    // Aplica búsqueda por nombre + filtro de estado.
    final q = _busqueda.text.trim().toLowerCase();
    final filtradas = _materias.where((m) {
      if (q.isNotEmpty && !m.materia.toLowerCase().contains(q)) return false;
      if (_filtroEstado == 'Todas') return true;
      final cat = _categoria(m); // 0 en curso, 1 próxima, 2 terminada
      if (_filtroEstado == 'En curso') return cat == 0;
      if (_filtroEstado == 'Próximas') return cat == 1;
      if (_filtroEstado == 'Terminadas') return cat == 2;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(
            children: [
              // Buscador por nombre.
              TextField(
                controller: _busqueda,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar materia por nombre…',
                  prefixIcon: const Icon(Icons.search, color: cessumRed),
                  suffixIcon: _busqueda.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () =>
                              setState(() => _busqueda.clear()),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: _superficie,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: cessumRed.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: cessumRed.withValues(alpha: 0.25)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Filtro de estado (chips).
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ['Todas', 'En curso', 'Próximas', 'Terminadas']
                      .map((op) {
                    final activo = _filtroEstado == op;
                    // Cuántas hay en ese estado.
                    final n = op == 'Todas'
                        ? _materias.length
                        : _materias.where((m) {
                            final c = _categoria(m);
                            return (op == 'En curso' && c == 0) ||
                                (op == 'Próximas' && c == 1) ||
                                (op == 'Terminadas' && c == 2);
                          }).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(n > 0 ? '$op ($n)' : op),
                        selected: activo,
                        selectedColor: cessumRed.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: activo ? cessumRed : cessumMuted(context),
                          fontWeight:
                              activo ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (_) =>
                            setState(() => _filtroEstado = op),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtradas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      q.isNotEmpty
                          ? 'No hay materias que coincidan con "$q".'
                          : 'No tienes materias en este estado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: cessumMuted(context)),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 4),
                      child: Text(
                        'Mostrando ${filtradas.length} de ${_materias.length} materia(s).',
                        style: TextStyle(
                            fontSize: 12.5, color: cessumMuted(context)),
                      ),
                    ),
                    ...filtradas.map(_tarjeta),
                  ],
                ),
        ),
      ],
    );
  }

  DateTime? _fechaParse(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m1 != null) {
      return DateTime(int.parse(m1.group(1)!), int.parse(m1.group(2)!),
          int.parse(m1.group(3)!));
    }
    final m2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m2 != null) {
      return DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!),
          int.parse(m2.group(1)!));
    }
    // Formato nativo de Date: "Sun Jun 28 2026 00:00:00 GMT-0700 (...)".
    // Es lo que manda el backend en muchos casos; sin esto, el parser fallaba
    // y TODAS las materias caían en "Próxima" por defecto.
    const meses = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final m3 =
        RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})').firstMatch(s);
    if (m3 != null) {
      final mes = meses[m3.group(1)!.toLowerCase()];
      if (mes != null) {
        return DateTime(
            int.parse(m3.group(3)!), mes, int.parse(m3.group(2)!));
      }
    }
    return null;
  }

  // 0 = en curso, 1 = próxima, 2 = terminada.
  int _categoria(_MateriaAsignada m) {
    final hoy = DateTime.now();
    final ini = _fechaParse(m.inicio);
    final fin = _fechaParse(m.termino);
    // Si ya pasó el término, está terminada (lo más importante de acertar).
    if (fin != null && hoy.isAfter(fin.add(const Duration(days: 1)))) return 2;
    // Si aún no llega el inicio, es próxima.
    if (ini != null && hoy.isBefore(ini)) return 1;
    // Si tenemos alguna fecha y no cayó en los casos anteriores, está en curso.
    if (ini != null || fin != null) return 0;
    // Sin ninguna fecha legible: en curso por defecto (no "próxima"), para no
    // esconder materias vigentes bajo un filtro de próximas.
    return 0;
  }

  Widget _badgeEstado(_MateriaAsignada m) {
    final cat = _categoria(m);
    final txt = cat == 0 ? 'En curso' : (cat == 1 ? 'Próxima' : 'Terminada');
    final color = cat == 0
        ? const Color(0xFF1E8E3E)
        : (cat == 1 ? const Color(0xFFA56B16) : Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _tarjeta(_MateriaAsignada m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.menu_book, color: cessumRed, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m.materia,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textoFuerte,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _badgeEstado(m),
            ],
          ),
          const SizedBox(height: 12),
          _renglon(Icons.school_outlined, m.programa),
          _renglon(Icons.groups_outlined,
              'Gen. ${m.generacion}  •  ${m.grupo}'),
          if (m.dia.isNotEmpty || m.hora.isNotEmpty)
            _renglon(Icons.schedule,
                [m.dia, m.hora].where((x) => x.isNotEmpty).join('  •  ')),
          if (m.tipoSesiones.isNotEmpty)
            _renglon(Icons.event_outlined, m.tipoSesiones),
          if (m.clave.isNotEmpty)
            _renglon(Icons.tag, 'Clave: ${m.clave}'),
          if (m.ciclo.isNotEmpty)
            _renglon(Icons.layers_outlined, 'Ciclo: ${m.ciclo}'),
          if (m.inicio.isNotEmpty || m.termino.isNotEmpty)
            _renglon(Icons.date_range,
                'Vigente: ${_fechaBonita(m.inicio)}  →  ${_fechaBonita(m.termino)}'),
          const SizedBox(height: 10),
          if (m.linkLlamada.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () => _abrirLink(m.linkLlamada),
                  icon: const Icon(Icons.videocam, size: 18),
                  label: const Text('Entrar a la videollamada'),
                ),
              ),
            ),
          if (m.linkAula.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  onPressed: () => _abrirLink(m.linkAula),
                  icon: const Icon(Icons.cast_for_education, size: 18),
                  label: const Text('Abrir el Aula CESSUM'),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumGold,
                side: const BorderSide(color: cessumGold),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () async {
                final nombre = await SessionStore.name();
                final correo = await SessionStore.validEmail();
                final docente = (nombre != null && nombre.isNotEmpty)
                    ? nombre
                    : (correo ?? '');
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SolicitarCorreccionScreen(
                      programa: m.programa,
                      generacion: m.generacion,
                      grupo: m.grupo,
                      materia: m.materia,
                      docente: docente,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Solicitar corrección'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirLink(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace.')),
        );
      }
    }
  }

  Widget _renglon(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _textoSuave),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  fontSize: 13, color: _textoSuave, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _suplantando
                  ? 'Estás viendo la cuenta de $_correoUsado y no tiene materias asignadas.'
                  : 'No tienes materias asignadas en este momento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              _suplantando
                  ? 'Sal del modo "Ver como..." para volver a tus propias materias.'
                  : 'Consultado con: $_correoUsado\nSi crees que esto es un error, comunícate con la Vicerrectoría.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: cessumMuted(context), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed, width: 1.5),
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
