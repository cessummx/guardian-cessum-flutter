// selector_buscable.dart · CESSUM · (24-sep-2026)
//
// SELECTOR CON BÚSQUEDA, reutilizable.
// Regla de la app: los selectores con muchas opciones (docentes, grupos,
// generaciones, alumnos…) deben tener búsqueda por texto, nada de listas
// planas largas. Este widget se ve igual que un DropdownButtonFormField
// (etiqueta, borde y flecha), pero al tocarlo abre una ventana con buscador
// que no distingue mayúsculas ni acentos.
//
// Uso:
//   CessumSelectorBuscable<String>(
//     label: 'Maestro',
//     valor: _docente,                 // null = sin elegir
//     opciones: listaDeDocentes,
//     etiqueta: (d) => d,
//     textoNinguno: 'Todos',           // opcional: primera opción que vale null
//     onChanged: (v) => setState(() => _docente = v),
//   )
import 'package:flutter/material.dart';

import 'cessum_ui.dart';
import 'constants.dart';

class CessumSelectorBuscable<T> extends StatelessWidget {
  final String label;
  final T? valor;
  final List<T> opciones;
  final String Function(T) etiqueta;
  final ValueChanged<T?>? onChanged;

  /// Si se da, aparece como primera opción y equivale a «ninguno» (null).
  final String? textoNinguno;

  /// Texto cuando no hay nada elegido y no hay [textoNinguno].
  final String? hint;

  /// Decoración propia (se le agrega la etiqueta y la flecha).
  final InputDecoration? decoracion;

  const CessumSelectorBuscable({
    super.key,
    required this.label,
    required this.valor,
    required this.opciones,
    required this.etiqueta,
    required this.onChanged,
    this.textoNinguno,
    this.hint,
    this.decoracion,
  });

  static String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  Future<void> _abrir(BuildContext context) async {
    final busca = TextEditingController();
    final elegido = await showDialog<_Eleccion<T>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = _norm(busca.text);
          final vis = q.isEmpty
              ? opciones
              : opciones.where((o) => _norm(etiqueta(o)).contains(q)).toList();
          return AlertDialog(
            title: Text(label, style: const TextStyle(fontSize: 16)),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: busca,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: busca.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setS(() => busca.clear()),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${vis.length} de ${opciones.length}',
                      style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView(
                    children: [
                      if (textoNinguno != null && q.isEmpty)
                        ListTile(
                          dense: true,
                          title: Text(textoNinguno!,
                              style: TextStyle(fontStyle: FontStyle.italic, color: cessumInk(ctx))),
                          trailing: valor == null ? const Icon(Icons.check, color: cessumRed, size: 18) : null,
                          onTap: () => Navigator.pop(ctx, _Eleccion<T>(null)),
                        ),
                      for (final o in vis)
                        ListTile(
                          dense: true,
                          title: Text(etiqueta(o), style: TextStyle(color: cessumInk(ctx))),
                          trailing: o == valor ? const Icon(Icons.check, color: cessumRed, size: 18) : null,
                          onTap: () => Navigator.pop(ctx, _Eleccion<T>(o)),
                        ),
                      if (vis.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                              child: Text('Nada coincide con «${busca.text}».',
                                  style: TextStyle(color: cessumMuted(ctx)))),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
    busca.dispose();
    if (elegido != null) onChanged?.call(elegido.valor);
  }

  @override
  Widget build(BuildContext context) {
    final texto = valor == null ? (textoNinguno ?? hint ?? '') : etiqueta(valor as T);
    final base = decoracion ?? const InputDecoration(isDense: true, border: OutlineInputBorder());
    return InkWell(
      onTap: onChanged == null ? null : () => _abrir(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: texto.isEmpty,
        decoration: base.copyWith(
          labelText: label,
          enabled: onChanged != null,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            color: valor == null && textoNinguno == null ? cessumMuted(context) : cessumInk(context),
          ),
        ),
      ),
    );
  }
}

/// Envoltura para distinguir «eligió ninguno (null)» de «canceló».
class _Eleccion<T> {
  final T? valor;
  const _Eleccion(this.valor);
}
