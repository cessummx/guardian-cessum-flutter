// INVITA A ALGUIEN · pantalla de referidos del alumno  (19-ago-2026)
//
// POR QUÉ ESTA PANTALLA ES CORTA
// Quien la abre ya está convencido de estudiar aquí; no hay que venderle
// nada. Lo único que tiene que pasar es que COMPARTA, y eso se cae por dos
// razones: porque no sabe qué escribir, o porque lo deja para después.
//
// Así que el mensaje viene redactado y el botón de WhatsApp está a un toque.
// Todo lo demás —cómo funciona, qué gana, quiénes llegaron— va debajo, para
// quien quiera leerlo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

class ReferidosScreen extends StatefulWidget {
  const ReferidosScreen({super.key});

  @override
  State<ReferidosScreen> createState() => _ReferidosScreenState();
}

class _ReferidosScreenState extends State<ReferidosScreen> {
  Map<String, dynamic>? _d;
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = await SessionStore.validEmail();
      if (correo == null || correo.isEmpty) {
        throw Exception('Inicia sesión de nuevo.');
      }
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'referido_mio',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Invita a alguien'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error),
                    const SizedBox(height: 10),
                    TextButton(
                        onPressed: _cargar, child: const Text('Reintentar')),
                  ]),
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    final d = _d!;
    final refs = (d['referidos'] as List?) ?? [];
    final inscritos = (d['inscritos'] as num?)?.toInt() ?? 0;
    final total = (d['total'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // ── Lo primero: por qué su recomendación vale ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu palabra vale más que un anuncio',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  'Quien está pensando en estudiar tiene una duda que ninguna '
                  'publicidad puede resolverle: si de verdad se puede con el '
                  'trabajo. Tú ya sabes la respuesta, y por eso a ti te creen.',
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5, color: cessumInk(context))),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── El botón que importa ──
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E7B34),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () async {
              final u = Uri.parse('${d['whatsapp']}');
              await launchUrl(u, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.chat, size: 21),
            label: const Text('Compartir por WhatsApp',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        // El mensaje ya escrito, visible: nadie comparte algo que no leyó.
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ESTO SE VA A ENVIAR · puedes editarlo allá',
                  style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w800,
                      color: cessumGold)),
              const SizedBox(height: 6),
              Text('${d['mensaje']}',
                  style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Su código, para dictarlo ──
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TU CÓDIGO',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: .9,
                          fontWeight: FontWeight.w800,
                          color: cessumRed)),
                  Text('${d['codigo']}',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  Text('Sirve para dictarlo por teléfono o en persona.',
                      style: TextStyle(
                          fontSize: 11, color: cessumMuted(context))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${d['enlace']}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Enlace copiado')));
            },
            icon: const Icon(Icons.link),
            tooltip: 'Copiar mi enlace',
          ),
        ]),
        const SizedBox(height: 18),

        // ── Cómo va ──
        if (total > 0) ...[
          Row(children: [
            Expanded(child: _cifra('$total', 'personas llegaron', cessumGold)),
            const SizedBox(width: 10),
            Expanded(child: _cifra('$inscritos', 'ya se inscribieron',
                const Color(0xFF1E7B34))),
          ]),
          const SizedBox(height: 12),
          ...refs.map((e) {
            final r = e as Map;
            final listo = '${r['estado']}' == 'Ya se inscribió';
            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: listo
                        ? const Color(0xFF1E7B34).withValues(alpha: 0.35)
                        : cessumMuted(context).withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                Icon(listo ? Icons.check_circle : Icons.schedule,
                    size: 18,
                    color: listo
                        ? const Color(0xFF1E7B34)
                        : cessumMuted(context)),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['nombre']}',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Text(
                          '${r['estado']}'
                          '${'${r['programa']}'.isNotEmpty ? ' · ${r['programa']}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
                Text('${r['fecha']}',
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ]),
            );
          }),
          const SizedBox(height: 8),
          Text('${d['nota']}',
              style: TextStyle(
                  fontSize: 11, height: 1.45, color: cessumMuted(context))),
          const SizedBox(height: 18),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Text(
                'Todavía no ha llegado nadie con tu código. En cuanto alguien '
                'pida informes con tu enlace, lo vas a ver aquí.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: cessumMuted(context))),
          ),
          const SizedBox(height: 18),
        ],

        // ── Qué gana y cómo funciona ──
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFF1E7B34).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // (17-sep) LOS DOS BENEFICIOS, NO SOLO EL PROPIO.
              // La pantalla decía únicamente lo que gana quien invita, así
              // que el alumno no tenía cómo saber que a la persona que
              // recomienda también le corresponde algo — y ese es justo el
              // argumento que hace que valga la pena mandar el mensaje.
              const Text('Qué gana cada quien',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 74,
                  child: Text('Tú',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: cessumMuted(context))),
                ),
                Expanded(
                  child: Text('${d['premio']}',
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              ]),
              if ('${d['premioReferido'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 74,
                    child: Text('Quien llega',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: cessumMuted(context))),
                  ),
                  Expanded(
                    child: Text('${d['premioReferido']}, al presentar tu código.',
                        style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              const Text('Cómo funciona',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              ...((d['comoFunciona'] as List?) ?? []).map((x) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('· ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                              child: Text('$x',
                                  style: const TextStyle(
                                      fontSize: 12.5, height: 1.45))),
                        ]),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
            'Invita solo a quien de verdad creas que le sirve. Una '
            'recomendación honesta vale; una lista de nombres para juntar '
            'descuentos no le sirve a nadie, y menos a quien recibe la '
            'llamada.',
            style: TextStyle(
                fontSize: 11.5, height: 1.5, color: cessumMuted(context))),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _cifra(String n, String t, Color c) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: c)),
            Text(t,
                style: TextStyle(
                    fontSize: 11.5, height: 1.3, color: cessumInk(context))),
          ],
        ),
      );
}
