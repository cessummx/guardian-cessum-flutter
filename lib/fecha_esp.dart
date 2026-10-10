/// Convierte cualquier fecha que mande el backend a un texto en español.
///
/// Acepta:
///  - Inglés tipo "Mon Jun 22 2026 14:46:00 GMT-0700 (Pacific Daylight Time)"
///  - ISO "2026-06-22T14:46:00" o "2026-06-22 14:46:00"
///  - "dd/MM/yyyy" o "dd/MM/yyyy HH:mm"
///
/// Devuelve por ejemplo: "22 de junio de 2026, 14:46".
/// Si no logra interpretarla, regresa el texto original sin romper nada.
library;

const List<String> _mesesEs = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];

const Map<String, int> _mesesEn = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
};

String _dos(int n) => n < 10 ? '0$n' : '$n';

/// Resultado interno: año, mes, día, hora, minuto (hora/minuto pueden ser -1).
class _F {
  final int y, m, d, h, min;
  _F(this.y, this.m, this.d, this.h, this.min);
}

_F? _parse(String s) {
  // 1) Inglés "EEE MMM dd yyyy HH:mm:ss ..."
  final en = RegExp(
          r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})(?:\s+(\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (en != null) {
    final mes = _mesesEn[en.group(1)!.toLowerCase()];
    if (mes != null) {
      return _F(
        int.parse(en.group(3)!),
        mes,
        int.parse(en.group(2)!),
        en.group(4) != null ? int.parse(en.group(4)!) : -1,
        en.group(5) != null ? int.parse(en.group(5)!) : -1,
      );
    }
  }
  // 2) ISO "yyyy-MM-dd" (con o sin hora).
  final iso = RegExp(
          r'(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (iso != null) {
    return _F(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
      iso.group(4) != null ? int.parse(iso.group(4)!) : -1,
      iso.group(5) != null ? int.parse(iso.group(5)!) : -1,
    );
  }
  // 3) "dd/MM/yyyy" (con o sin hora).
  final dmy = RegExp(
          r'(\d{1,2})/(\d{1,2})/(\d{4})(?:[ ,]+(\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (dmy != null) {
    return _F(
      int.parse(dmy.group(3)!),
      int.parse(dmy.group(2)!),
      int.parse(dmy.group(1)!),
      dmy.group(4) != null ? int.parse(dmy.group(4)!) : -1,
      dmy.group(5) != null ? int.parse(dmy.group(5)!) : -1,
    );
  }
  return null;
}

/// Fecha en español: "22 de junio de 2026, 14:46" (omite la hora si no hay
/// o si es 00:00).
String fechaEsp(dynamic value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty) return '';
  final f = _parse(s);
  if (f == null || f.m < 1 || f.m > 12) return s;
  final fecha = '${f.d} de ${_mesesEs[f.m - 1]} de ${f.y}';
  if (f.h >= 0 && f.min >= 0 && !(f.h == 0 && f.min == 0)) {
    return '$fecha, ${_dos(f.h)}:${_dos(f.min)}';
  }
  return fecha;
}

/// Igual que [fechaEsp] pero sin la hora (solo día, mes y año).
String fechaEspCorta(dynamic value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty) return '';
  final f = _parse(s);
  if (f == null || f.m < 1 || f.m > 12) return s;
  return '${f.d} de ${_mesesEs[f.m - 1]} de ${f.y}';
}
