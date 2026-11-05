import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../models/transporte_models.dart';

class MemoriaGps {
  double eta;
  int timestampMs;
  String? st;
  bool passou;

  MemoriaGps({
    this.eta = 0,
    required this.timestampMs,
    this.st,
    this.passou = false,
  });
}

class ViagemProgramada {
  final int m;
  final int ini;
  final String r;
  final String l;
  final ShapeLinha? sh;

  ViagemProgramada({
    required this.m,
    required this.ini,
    required this.r,
    required this.l,
    this.sh,
  });
}

class SituacaoCalculada {
  final ViagemProgramada x;
  final String c; // 'term', 'cheg', 'prev', 'saindo', 'prog', 'off'
  final String t;
  final String sub;
  double? e;
  double? h;

  SituacaoCalculada({
    required this.x,
    required this.c,
    required this.t,
    required this.sub,
    this.e,
    this.h,
  });
}

class GrupoLinhaOperacional {
  final String id;
  final String? s;
  final List<String> ids;
  String nome;
  Color cor;
  Map<String, dynamic> cfg;
  Map<String, List<ViagemProgramada>> t;
  Map<String, Map<int, ShapeLinha>> b;
  String ala;
  String dest;

  GrupoLinhaOperacional({
    required this.id,
    this.s,
    required this.ids,
    required this.nome,
    required this.cor,
    required this.cfg,
    required this.t,
    required this.b,
    this.ala = '',
    this.dest = '',
  });
}

class MarcasVariantesResult {
  final Map<int, String> m; // shapeIndex -> sigla/letra
  final List<List<String>> leg; // [[sigla, descricao], ...]
  final bool sig;
  final Set<int> ast;

  MarcasVariantesResult({
    required this.m,
    required this.leg,
    required this.sig,
    required this.ast,
  });
}

class PernaViagem {
  final LinhaOnibus l;
  final int si;
  final int k0;
  final double f0;
  final int k1;
  final double f1;
  final int t0; // Horário de embarque
  final int t1; // Horário de descida
  final int m; // Minuto de saída do ponto inicial
  final bool lv; // Calculado com GPS ao vivo

  PernaViagem({
    required this.l,
    required this.si,
    required this.k0,
    required this.f0,
    required this.k1,
    required this.f1,
    required this.t0,
    required this.t1,
    required this.m,
    this.lv = false,
  });
}

class OpcaoViagem {
  final List<PernaViagem> legs;
  final int wo; // Minutos a pé na origem
  final int wd; // Minutos a pé no destino
  final int wt; // Minutos a pé na troca
  final double dO; // Metros até o 1º ponto
  final double dD; // Metros do último ponto ao destino
  final double dT; // Metros na troca
  final bool ttu; // Troca dentro do TTU
  final int chega;
  final int sai;
  double custo;
  double pref;
  List alt = [];
  int? rO; // Distância real pela rua (origem)
  int? rD; // Distância real pela rua (destino)
  int? rT; // Distância real pela rua (troca)

  OpcaoViagem({
    required this.legs,
    required this.wo,
    required this.wd,
    this.wt = 0,
    required this.dO,
    required this.dD,
    this.dT = 0,
    this.ttu = false,
    required this.chega,
    required this.sai,
    this.custo = 0,
    this.pref = 0,
  });
}

class ResultadoPlanejamento {
  final List<OpcaoViagem> ops;
  final bool semPonto;
  final bool semServ;
  final bool pertoAPe;
  final int metrosDireto;

  ResultadoPlanejamento({
    required this.ops,
    this.semPonto = false,
    this.semServ = false,
    this.pertoAPe = false,
    this.metrosDireto = 0,
  });
}

class MotorHorarios {
  static final double kx = 111320.0 * math.cos(-25.52 * math.pi / 180.0);
  static const double ky = 110540.0;
  static final RegExp espRe =
      RegExp(r'(^|[^A-Za-zÀ-ÿ])ESP([^A-Za-zÀ-ÿ]|$)', caseSensitive: false);

  static const int memMaxMinutos = 15;
  static final Map<String, MemoriaGps> mem = {};

  // Constantes do Planejador de Viagens (idênticas ao index.html)
  static const double andaMetrosPorMin = 70.0;
  static const double raioPeMax = 800.0;
  static const double raioTerm = 150.0;
  static const double raioPonto = 60.0;
  static const double raioTroca = 250.0;
  static const double raioComoda = 60.0;
  static const int tempoIntegracaoMin = 90;
  static const int folgaTrocaMin = 3;

  static double dist(double a, double b, double c, double d) {
    final dx = (b - d) * kx;
    final dy = (a - c) * ky;
    return math.sqrt(dx * dx + dy * dy);
  }

  static int aPeMinutos(double m) =>
      math.max(1, (m * 1.25 / andaMetrosPorMin).round());

  static int arredonda10(num m) => math.max(10, (m / 10.0).round() * 10);

  static String hm(num m) {
    final totalMin = m.round();
    final hh = ((totalMin ~/ 60) % 24).toString().padLeft(2, '0');
    final mm = (totalMin % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static String semAcento(String? t) {
    if (t == null || t.isEmpty) return '';
    const comAc = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const semAc = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
    var str = t;
    for (int i = 0; i < comAc.length; i++) {
      str = str.replaceAll(comAc[i], semAc[i]);
    }
    return str.toUpperCase();
  }

  static DateTime diaOper([DateTime? ref]) {
    final n = ref ?? DateTime.now();
    if (n.hour < 3) return n.subtract(const Duration(days: 1));
    return n;
  }

  static String isoDe(DateTime n) {
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String tipoDia(DadosTransporteGeral d, [DateTime? ref]) {
    final n = diaOper(ref);
    final iso = isoDe(n);
    final e = d.especiais[iso];
    if (e is Map && e['tabela'] != null) {
      final tab = e['tabela'].toString();
      if (RegExp(r'^(DU|SAB|DOM)$').hasMatch(tab)) return tab;
    }
    final f = d.feriados[iso]?.toString();
    if (f == 'DU' || f == 'SAB' || f == 'DOM') return f!;
    if (n.weekday == DateTime.sunday) return 'DOM';
    if (n.weekday == DateTime.saturday) return 'SAB';
    return 'DU';
  }

  static double agora([DateTime? ref]) {
    final d = ref ?? DateTime.now();
    final m = d.hour * 60.0 + d.minute + d.second / 60.0;
    return m < 180 ? m + 1440 : m;
  }

  static int agoraMin([DateTime? ref]) => agora(ref).floor();

  static Color shadeColor(String hex, int p) {
    final cleanHex = hex.replaceFirst('#', '');
    final n = int.parse(cleanHex, radix: 16);
    final r = (n >> 16) & 255;
    final g = (n >> 8) & 255;
    final b = n & 255;
    int f(int v) {
      final calc = p < 0 ? v * (1 + p / 100.0) : v + (255 - v) * p / 100.0;
      return calc.round().clamp(0, 255);
    }
    return Color.fromARGB(255, f(r), f(g), f(b));
  }

  static double _lumi(Color c) {
    double f(int v) {
      final x = v / 255.0;
      return x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }
    return 0.2126 * f(c.red) + 0.7152 * f(c.green) + 0.0722 * f(c.blue);
  }

  static double _contraste(Color a, Color b) {
    final x = _lumi(a) + 0.05;
    final y = _lumi(b) + 0.05;
    return x > y ? x / y : y / x;
  }

  static List<Color> fundoTinta(Color corBase) {
    var c = corBase;
    const white = Color(0xFFFFFFFF);
    const dark = Color(0xFF14212B);
    for (int k = 0; k < 12; k++) {
      if (_contraste(c, white) >= 4.5) return [c, white];
      if (_contraste(c, dark) >= 4.5) return [c, dark];
      c = Color.fromARGB(
        255,
        (c.red * 0.94).round(),
        (c.green * 0.94).round(),
        (c.blue * 0.94).round(),
      );
    }
    return [c, white];
  }

  static String familiaLinha(LinhaOnibus l) {
    if (l.esc) return 'fe';
    final n = int.tryParse(l.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    return n < 100
        ? 'f0'
        : n < 200
            ? 'f1'
            : n < 300
                ? 'f2'
                : 'f3';
  }

  /// Inicializa cores, filtra viagens ESP e vincula paradas (idêntico ao início do `app(D)` no index.html)
  static void inicializarDadosMapa(DadosTransporteGeral d) {
    const shOffsets = [0, -14, 12, -24, 20, -6, 28];
    final idx = <String, int>{};

    for (final l in d.linhas) {
      final f = familiaLinha(l);
      idx[f] = idx[f] ?? 0;
      final baseHex = AppConfig.familiaCoresHex[f] ?? '#1c62b9';
      l.cor = shadeColor(baseHex, shOffsets[idx[f]! % shOffsets.length]);
      final ft = fundoTinta(l.cor);
      l.bgc = ft[0];
      l.ink = ft[1];
      idx[f] = idx[f]! + 1;

      for (final s in l.shapes) {
        if (espRe.hasMatch(s.v)) {
          s.esp = true;
          s.main = 0;
        }
      }
      if (!l.shapes.any((s) => s.main == 1)) {
        final k = l.shapes.indexWhere((s) => !s.esp);
        if (k >= 0) l.shapes[k].main = 1;
      }

      // Normaliza horários < 180 (+1440), ordena e remove viagens ESP para o público
      l.dep.forEach((dk, sentidosMap) {
        final chavesRemover = <String>[];
        sentidosMap.forEach((sKey, listaPares) {
          final normalizados = listaPares
              .where((x) => x[1] >= 0 && x[1] < l.shapes.length && !l.shapes[x[1]].esp)
              .map((x) => [x[0] < 180 ? x[0] + 1440 : x[0], x[1]])
              .toList()
            ..sort((a, b) => a[0].compareTo(b[0]));
          if (normalizados.isEmpty) {
            chavesRemover.add(sKey);
          } else {
            sentidosMap[sKey] = normalizados;
          }
        });
        for (final k in chavesRemover) {
          sentidosMap.remove(k);
        }
      });
    }

    final byId = {for (final l in d.linhas.where((x) => !x.esc)) l.id: l};
    for (final s in d.stops) {
      s.xPlano = s.lon * kx;
      s.yPlano = s.lat * ky;
      s.linhasAtivas = [];
      for (int i = 0; i < s.linhasRaw.length; i++) {
        final lid = s.linhasRaw[i];
        if (byId.containsKey(lid)) {
          final sent = i < s.sentidosRaw.length ? s.sentidosRaw[i] : '';
          s.linhasAtivas.add(LinhaSentidoParada(id: lid, s: sent));
        }
      }
    }
  }

  static String cap(String? t) {
    if (t == null || t.isEmpty) return '';
    const minWords = {
      'o', 'a', 'os', 'as', 'e', 'de', 'da', 'do', 'das', 'dos', 'em', 'no', 'na', 'pela', 'pelo', 'ao'
    };
    bool ini = true;
    return t.splitMapJoin(
      RegExp(r'(\s+)'),
      onMatch: (m) => m.group(0)!,
      onNonMatch: (w) {
        if (w.trim().isEmpty) return w;
        if (w == '·' || w == '→') {
          ini = true;
          return w;
        }
        String r = w;
        final hasUpper =
            w.length > 1 && RegExp(r'[A-ZÀ-Ý]').hasMatch(w.substring(1));
        if (!hasUpper && !(!ini && minWords.contains(w.toLowerCase()))) {
          r = w[0].toUpperCase() + w.substring(1);
        }
        ini = false;
        return r;
      },
    );
  }

  static List<double> cumula(ShapeLinha sh) {
    if (sh.cum != null) return sh.cum!;
    final p = sh.p;
    final c = <double>[0.0];
    for (int i = 1; i < p.length; i++) {
      c.add(c[i - 1] +
          dist(p[i - 1].latitude, p[i - 1].longitude, p[i].latitude,
              p[i].longitude));
    }
    sh.cum = c;
    return c;
  }

  /// Ponto mais próximo sobre uma polilinha (`pertoDe` e `aoLongo` do index.html)
  static ({double d, double f, double lat, double lon}) aoLongo(
      ShapeLinha s, double lat, double lon) {
    final P = s.p;
    if (P.isEmpty) return (d: 1e9, f: 0.0, lat: lat, lon: lon);
    final c = cumula(s);
    final tot = c.last > 0 ? c.last : 1.0;
    final kxLocal = 111320.0 * math.cos(lat * math.pi / 180.0);
    double best = 1e18, fBest = 0.0, bx = 0.0, by = 0.0;

    for (int i = 1; i < P.length; i++) {
      final ax = (P[i - 1].longitude - lon) * kxLocal;
      final ay = (P[i - 1].latitude - lat) * ky;
      final dx = (P[i].longitude - lon) * kxLocal - ax;
      final dy = (P[i].latitude - lat) * ky - ay;
      final l2 = dx * dx + dy * dy;
      double t = l2 > 0 ? -(ax * dx + ay * dy) / l2 : 0.0;
      t = t.clamp(0.0, 1.0);
      final x = ax + t * dx;
      final y = ay + t * dy;
      final d2 = x * x + y * y;
      if (d2 < best) {
        best = d2;
        bx = x;
        by = y;
        fBest = c[i - 1] + t * (c[i] - c[i - 1]);
      }
    }
    return (
      d: math.sqrt(best),
      f: fBest / tot,
      lat: lat + by / ky,
      lon: lon + bx / kxLocal
    );
  }

  static double distLinha(LinhaOnibus l, double lat, double lon) {
    double b = 1e18;
    for (final s in l.shapes) {
      if (s.main == 1) {
        final d = aoLongo(s, lat, lon).d;
        if (d < b) b = d;
      }
    }
    return b;
  }

  // ── Estimativa de tempo de viagem ao longo do percurso (`minAte`, `minCedo`, `minTarde`) ──
  static double durS(ShapeLinha s, LinhaOnibus l, String dk, int m) {
    if (s.d > 0) return s.d.toDouble();
    final c = cumula(s);
    return (c.isNotEmpty ? c.last : 1000.0) / 1000.0 / 20.0 * 60.0;
  }

  static double fracTempo(ShapeLinha s, double f) {
    final g = s.g;
    if (g != null && g['p'] is List) {
      final q = (g['p'] as List).map((e) => (e as num).toDouble()).toList();
      if (q.length >= 11) {
        final x = (f * 10.0).clamp(0.0, 9.999);
        final i = x.floor();
        return (q[i] + (q[i + 1] - q[i]) * (x - i)) / 1000.0;
      }
    }
    return f;
  }

  static int minAte(LinhaOnibus l, ShapeLinha s, String dk, int m, double f) =>
      (durS(s, l, dk, m) * fracTempo(s, f)).round();

  static int minCedo(LinhaOnibus l, ShapeLinha s, String dk, int m, double f) =>
      (durS(s, l, dk, m) * fracTempo(s, f) * 0.88).floor();

  static int minTarde(LinhaOnibus l, ShapeLinha s, String dk, int m, double f) =>
      (durS(s, l, dk, m) * fracTempo(s, f) * 1.18).ceil();

  /// Próximas passagens estimadas de uma linha perto de (lat, lon) hoje
  static Map<String, int> passagens(
      LinhaOnibus l, String dk, double lat, double lon, double raio) {
    final now = agoraMin();
    final out = <String, int>{};
    final cacheF = <int, double?>{};
    final d = l.dep[dk] ?? {};

    d.forEach((sKey, pares) {
      int? best;
      for (int i = 0; i < pares.length; i++) {
        final m = pares[i][0];
        final si = pares[i][1];
        if (!cacheF.containsKey(si)) {
          final r = aoLongo(l.shapes[si], lat, lon);
          cacheF[si] = r.d <= raio ? r.f : null;
        }
        final f = cacheF[si];
        if (f == null) continue;
        final ce = m + minCedo(l, l.shapes[si], dk, m, f);
        final ta = m + minTarde(l, l.shapes[si], dk, m, f);
        if (ta < now) continue;
        final t = math.max(now, ce);
        if (best == null || t < best) best = t;
      }
      if (best != null) out[sKey] = best;
    });
    return out;
  }

  /// Recorta uma fatia da polilinha entre as frações f0 e f1 (`fatia` do index.html)
  static List<LatLng> fatia(ShapeLinha s, double f0, double f1) {
    final P = s.p;
    if (P.length < 2) return P;
    final c = cumula(s);
    final tot = c.last;
    final a = (f0.clamp(0.0, 1.0)) * tot;
    final b = (f1.clamp(0.0, 1.0)) * tot;
    if (b <= a) return [P.first, P.last];

    LatLng em(double dAlvo) {
      int i = 1;
      while (i < P.length - 1 && c[i] < dAlvo) {
        i++;
      }
      final denom = (c[i] - c[i - 1]);
      final t = denom > 0 ? (dAlvo - c[i - 1]) / denom : 0.0;
      return LatLng(
        P[i - 1].latitude + (P[i].latitude - P[i - 1].latitude) * t,
        P[i - 1].longitude + (P[i].longitude - P[i - 1].longitude) * t,
      );
    }

    final out = <LatLng>[em(a)];
    for (int i = 1; i < P.length - 1; i++) {
      if (c[i] > a && c[i] < b) out.add(P[i]);
    }
    out.add(em(b));
    return out;
  }

  // ── Siglas e Letras das Variantes no Quadro de Horários (`marcasVar`) ──
  static const Map<String, String> _mapaSigla = {
    'PTE': 'PTE', 'PONTE': 'PTE', 'GL': 'GL', 'CMP': 'CMP', 'CAMP': 'CMP',
    'CAMPUS': 'CMP', 'UNI': 'CMP', 'UNIOESTE': 'CMP', 'CTO': 'CTO',
    'CTRO': 'CTO', 'CENTRO': 'CTO', 'CETRO': 'CTO', 'DI': 'DI', 'DIR': 'DI',
    'DIRETO': 'DI', 'DIREITO': 'DI', 'DIRT': 'DI', 'MAC': 'MAC', 'AL': 'AL',
    'ALMADA': 'AL'
  };

  static const Set<String> _palavrasInternas = {
    'ESP', 'PRIM', 'PRIMEIRA', 'ULTIMA', 'VIAGEM', 'VIAJEM', 'VIJ', 'V',
    'REC', 'RC', 'RECOLHIMENTO', 'SOLTURA', 'RENDICAO', 'PARTE', '5MIN',
    'T10', 'T6', 'F', 'SABADO'
  };

  static const Map<String, String> _descSiglaGeral = {
    'N-S': 'Norte–Sul',
    'S-N': 'Sul–Norte',
    'N': 'Norte',
    'S': 'Sul',
    'PTE': 'Ponte',
    'GL': 'Grande Lago',
    'CMP': 'Unioeste',
    'CTO': 'Centro',
    'DI': 'Direto',
    'MAC': 'McDonald’s',
    'AL': 'Via Jd. Almada',
    'ATE': 'Só até o Terminal, não vai até o Centro',
    'DOT': 'Sai do Terminal, não passa no Centro',
  };

  static List<String> codigosVar(LinhaOnibus l, int si) {
    final sh = l.shapes[si];
    final v = sh.v;
    final m = RegExp(r'^\s*\[([^\]]*)\]\s*(.*)$').firstMatch(v);
    final colchete = m != null ? m.group(1)! : '';
    final resto = (m != null ? m.group(2)! : v)
        .replaceAll(RegExp(r'VILA\s+C(\s+(NORTE|SUL))?', caseSensitive: false), ' ');

    List<String> tok(String x) => semAcento(x)
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final tn = tok(resto);
    final tc = tok(colchete);

    final o = <String>[];
    if (l.id == '101' || l.id == '102') {
      List<String> extraiNS(List<String> a) {
        final res = <String>[];
        for (final x in a) {
          final val = (x == 'N' || x == 'NORTE')
              ? 'N'
              : (x == 'S' || x == 'SUL')
                  ? 'S'
                  : '';
          if (val.isNotEmpty && !res.contains(val)) res.add(val);
        }
        return res;
      }

      var ns = extraiNS(tn);
      final oc = extraiNS(tc);
      if (oc.length > ns.length) ns = oc;
      if (ns.isNotEmpty) o.add(ns.join('-'));
    }

    final tem = <String>{};
    for (final x in [...tn, ...tc]) {
      if (_mapaSigla.containsKey(x)) tem.add(_mapaSigla[x]!);
    }

    if (l.id == '10' && sh.p.isNotEmpty) {
      final a = sh.p.first, z = sh.p.last;
      final da = dist(a.latitude, a.longitude, AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]);
      final dz = dist(z.latitude, z.longitude, AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]);
      if (dz < 350 && da >= 350) tem.add('ATE');
      if (da < 350 && dz >= 350) tem.add('DOT');
    }

    final ordem = l.id == '10'
        ? ['DI', 'AL', 'MAC', 'CMP', 'ATE', 'DOT']
        : ['DI', 'PTE', 'GL', 'CMP', 'CTO', 'MAC'];
    for (final g in ordem) {
      if (tem.contains(g)) o.add(g);
    }
    return o;
  }

  static String nomeVarLimpo(LinhaOnibus l, int si) {
    var v = l.shapes[si].v
        .replaceFirst(RegExp(r'^\s*\[[^\]]*\]\s*'), '')
        .replaceAll(RegExp(r'\(\s*[^)]*\)'), ' ');
    final partes = v.split(RegExp(r'(\s+|[-–>\/.*]+)'));
    final limpas = partes
        .where((p) => !_palavrasInternas.contains(semAcento(p)))
        .join(' ');
    return limpas
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s\-–>\/.*]+|[\s\-–>\/.*]+$'), '')
        .trim();
  }

  static MarcasVariantesResult marcasVar(LinhaOnibus l, String dk, String s) {
    final pares = (l.dep[dk] ?? {})[s] ?? [];
    final cont = <int, int>{};
    for (final par in pares) {
      cont[par[1]] = (cont[par[1]] ?? 0) + 1;
    }
    final ord = cont.keys.toList()
      ..sort((x, y) {
        final cmp = cont[y]!.compareTo(cont[x]!);
        return cmp != 0 ? cmp : x.compareTo(y);
      });

    final m = <int, String>{};
    final leg = <List<String>>[];
    final ast = <int>{};

    if (l.id == '10' || l.id == '101' || l.id == '102') {
      final sep = l.id == '10' ? '-' : ' ';
      final usadas = <String>{};
      bool temAst = false;

      String rotuloSigla(String g) {
        if (l.id == '10') {
          if (g == 'CMP') return 'CMP UNI';
          if (g == 'ATE') return 'ATÉ TTU';
          if (g == 'DOT') return 'DO TTU';
        }
        return g;
      }

      for (final si in ord) {
        final cs = codigosVar(l, si);
        m[si] = cs.map(rotuloSigla).join(sep);
        usadas.addAll(cs);
        if (l.id == '10' && RegExp(r'5\s*MIN', caseSensitive: false).hasMatch(l.shapes[si].v)) {
          ast.add(si);
          temAst = true;
        }
      }

      final todasChaves = [
        'N-S', 'S-N', 'N', 'S', 'DI', 'PTE', 'GL', 'AL', 'MAC', 'CMP', 'CTO', 'ATE', 'DOT'
      ];
      for (final g in todasChaves) {
        if (usadas.contains(g)) {
          String desc = _descSiglaGeral[g] ?? g;
          if (l.id == '10') {
            if (g == 'DI') desc = 'Direto, não passa na região da Ponte';
            if (g == 'MAC') desc = 'Av. Jorge Schimmelpfeng, em frente ao McDonald’s';
            if (g == 'CMP') desc = 'Acessa o campus da Unioeste';
          }
          leg.add([rotuloSigla(g), desc]);
        }
      }
      if (temAst) {
        leg.add([
          '*',
          'Começa na Av. Andradina c/ R. Elói Armando Nedel e passa na R. Rafael Cazula 5 min depois'
        ]);
      }
      return MarcasVariantesResult(m: m, leg: leg, sig: true, ast: ast);
    }

    String chave(String t) => semAcento(t).replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final base = ord.isNotEmpty ? chave(nomeVarLimpo(l, ord.first)) : '';
    final letras = <String, String>{};
    int k = 0;

    for (final si in ord.skip(1)) {
      final n = nomeVarLimpo(l, si);
      final c = chave(n);
      if (c.isEmpty || c == base) continue;
      if (!letras.containsKey(c)) {
        final letra = String.fromCharCode(65 + (k++) % 26);
        letras[c] = letra;
        leg.add([letra, n]);
      }
      m[si] = letras[c]!;
    }
    if (leg.isNotEmpty) {
      final principal = ord.isNotEmpty ? nomeVarLimpo(l, ord.first) : l.nome;
      leg.insert(0, ['Sem letra:', principal.isNotEmpty ? principal : l.nome]);
    }
    return MarcasVariantesResult(m: m, leg: leg, sig: false, ast: ast);
  }

  // ── Planejador de Viagens A → B (Direto ou com 1 conexão em até 90 min) ──
  static bool _noTTU(PontoParada p) {
    p.noTtuCache ??= dist(p.lat, p.lon, AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]) <= 200.0;
    return p.noTtuCache!;
  }

  static void _xyShape(ShapeLinha s) {
    if (s.xPlano != null) return;
    final n = s.p.length;
    final xArr = List<double>.filled(n, 0.0);
    final yArr = List<double>.filled(n, 0.0);
    double minX = 1e18, maxX = -1e18, minY = 1e18, maxY = -1e18;
    for (int i = 0; i < n; i++) {
      final x = s.p[i].longitude * kx;
      final y = s.p[i].latitude * ky;
      xArr[i] = x;
      yArr[i] = y;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    s.xPlano = xArr;
    s.yPlano = yArr;
    s.bbox = [minX, maxX, minY, maxY];
    cumula(s);
  }

  static List<({double d, double f})> _passadas(
      ShapeLinha s, double x, double y, double R) {
    _xyShape(s);
    final bb = s.bbox!;
    if (x < bb[0] - R || x > bb[1] + R || y < bb[2] - R || y > bb[3] + R) {
      return [];
    }
    final X = s.xPlano!, Y = s.yPlano!, c = s.cum!;
    final n = X.length;
    if (n < 2) return [];
    final tot = c.last > 0 ? c.last : 1.0;
    final out = <({double d, double f})>[];
    ({double d, double f})? cur;

    for (int i = 1; i < n; i++) {
      final x0 = X[i - 1], y0 = Y[i - 1], x1 = X[i], y1 = Y[i];
      if ((x0 < x - R && x1 < x - R) ||
          (x0 > x + R && x1 > x + R) ||
          (y0 < y - R && y1 < y - R) ||
          (y0 > y + R && y1 > y + R)) {
        if (cur != null) {
          out.add(cur);
          cur = null;
        }
        continue;
      }
      final ax = x0 - x, ay = y0 - y, dx = x1 - x0, dy = y1 - y0;
      final l2 = dx * dx + dy * dy;
      double t = l2 > 0 ? -(ax * dx + ay * dy) / l2 : 0.0;
      t = t.clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d <= R) {
        if (cur == null || d < cur.d) {
          cur = (d: d, f: (c[i - 1] + t * (c[i] - c[i - 1])) / tot);
        }
      } else if (cur != null) {
        out.add(cur);
        cur = null;
      }
    }
    if (cur != null) out.add(cur);
    return out;
  }

  static List<PontoTrajetoRef> pontosDoTrajeto(
      DadosTransporteGeral d, LinhaOnibus l, int si) {
    final s = l.shapes[si];
    if (s.stCache != null) return s.stCache!;
    final res = <PontoTrajetoRef>[];

    for (int k = 0; k < d.stops.length; k++) {
      final p = d.stops[k];
      final o = p.linhasAtivas.where((x) => x.id == l.id).firstOrNull;
      if (o == null) continue;
      final term = _noTTU(p);
      final pass = _passadas(s, p.xPlano, p.yPlano, term ? raioTerm : raioPonto);
      for (final r in pass) {
        res.add(PontoTrajetoRef(k: k, f: r.f, lado: 0));
      }
    }
    s.stCache = res;
    return res;
  }

  static List<int> _viagensShape(LinhaOnibus l, int si, String dk) {
    final out = <int>[];
    final d = l.dep[dk] ?? {};
    d.forEach((_, pares) {
      for (final par in pares) {
        if (par[1] == si) out.add(par[0]);
      }
    });
    out.sort();
    return out;
  }

  static List<int>? _primeiraViagem(
      LinhaOnibus l, int si, String dk, double f, int t0) {
    final s = l.shapes[si];
    final a = _viagensShape(l, si, dk);
    for (final m in a) {
      final p = m + minCedo(l, s, dk, m, f);
      if (p >= t0) return [m, p];
    }
    return null;
  }

  static ResultadoPlanejamento planejarViagem(
    DadosTransporteGeral d,
    LatLng origem,
    LatLng destino, {
    String? dkCustom,
    int? minutoPartidaCustom,
  }) {
    final dk = dkCustom ?? tipoDia(d);
    final t0 = minutoPartidaCustom ?? agoraMin();
    final dOX = dist(
        origem.latitude, origem.longitude, destino.latitude, destino.longitude);

    List<({LinhaOnibus l, int si, int k, double f, double d})> candidatos(
        LatLng P) {
      final por = <String,
          List<({LinhaOnibus l, int si, int k, double f, double d})>>{};
      final byId = {for (final l in d.linhas.where((x) => !x.esc)) l.id: l};

      for (int k = 0; k < d.stops.length; k++) {
        final p = d.stops[k];
        final distP = dist(p.lat, p.lon, P.latitude, P.longitude);
        if (distP > raioPeMax) continue;
        for (final o in p.linhasAtivas) {
          final l = byId[o.id];
          if (l == null) continue;
          for (int si = 0; si < l.shapes.length; si++) {
            if (_viagensShape(l, si, dk).isEmpty) continue;
            final pts = pontosDoTrajeto(d, l, si);
            for (final q in pts) {
              if (q.k == k) {
                final key = '${l.id}|$si';
                por.putIfAbsent(key, () => []).add(
                    (l: l, si: si, k: k, f: q.f, d: distP));
              }
            }
          }
        }
      }
      final out = <({LinhaOnibus l, int si, int k, double f, double d})>[];
      por.forEach((_, lista) {
        lista.sort((a, b) => a.d.compareTo(b.d));
        out.add(lista.first);
        final seg =
            lista.where((x) => (x.f - lista.first.f).abs() > 0.15).firstOrNull;
        if (seg != null) out.add(seg);
      });
      return out;
    }

    final E = candidatos(origem);
    final S = candidatos(destino);
    if (E.isEmpty) {
      final temPontoPerto = d.stops.any((p) =>
          dist(p.lat, p.lon, origem.latitude, origem.longitude) <= raioPeMax);
      return ResultadoPlanejamento(
        ops: [],
        semPonto: !temPontoPerto,
        semServ: temPontoPerto,
        pertoAPe: dOX <= raioPeMax,
        metrosDireto: arredonda10(dOX),
      );
    }

    double lenShape(LinhaOnibus l, int si) {
      final c = cumula(l.shapes[si]);
      return c.isNotEmpty ? c.last : 0.0;
    }

    double calculaCusto(OpcaoViagem o) =>
        o.chega +
        0.5 * (o.wo + o.wd + o.wt) +
        0.25 * (o.chega - o.sai) +
        (o.legs.length > 1 ? (o.ttu ? 2 : 10) : 0);

    final ops = <OpcaoViagem>[];

    // 1. Viagens diretas (sem troca)
    for (final e in E) {
      for (final x in S) {
        if (e.l.id != x.l.id ||
            e.si != x.si ||
            (x.f - e.f) * lenShape(e.l, e.si) < 300) {
          continue;
        }
        final wo = aPeMinutos(e.d);
        final v = _primeiraViagem(e.l, e.si, dk, e.f, t0 + wo);
        if (v == null) continue;
        final tD = v[0] + minAte(e.l, e.l.shapes[e.si], dk, v[0], x.f);
        final wd = aPeMinutos(x.d);
        if (tD <= v[1]) continue;

        final op = OpcaoViagem(
          legs: [
            PernaViagem(
              l: e.l,
              si: e.si,
              k0: e.k,
              f0: e.f,
              k1: x.k,
              f1: x.f,
              t0: v[1],
              t1: tD,
              m: v[0],
            )
          ],
          wo: wo,
          wd: wd,
          dO: e.d,
          dD: x.d,
          chega: tD + wd,
          sai: v[1] - wo,
        );
        op.custo = calculaCusto(op);
        ops.add(op);
      }
    }

    // 2. Viagens com 1 troca (integração de até 90 min)
    for (final e in E) {
      final wo = aPeMinutos(e.d);
      final v = _primeiraViagem(e.l, e.si, dk, e.f, t0 + wo);
      if (v == null) continue;
      final la = lenShape(e.l, e.si);
      final ptsA = pontosDoTrajeto(d, e.l, e.si)
          .where((pa) => (pa.f - e.f) * la >= 300)
          .toList();
      if (ptsA.isEmpty) continue;

      for (final x in S) {
        if (x.l.id == e.l.id && x.si == e.si) continue;
        final lb = lenShape(x.l, x.si);
        final ptsB = pontosDoTrajeto(d, x.l, x.si)
            .where((pb) => (x.f - pb.f) * lb >= 300)
            .toList();
        if (ptsB.isEmpty) continue;

        OpcaoViagem? melhorTroca;
        for (final pa in ptsA) {
          final stopA = d.stops[pa.k];
          for (final pb in ptsB) {
            if (x.l.id == e.l.id && !(_noTTU(stopA) && _noTTU(d.stops[pb.k]))) {
              continue;
            }
            final stopB = d.stops[pb.k];
            final dx = (stopA.xPlano - stopB.xPlano).abs();
            if (dx > raioTroca) continue;
            final dy = (stopA.yPlano - stopB.yPlano).abs();
            if (dy > raioTroca) continue;
            final distTr = math.sqrt(dx * dx + dy * dy);
            if (distTr > raioTroca) continue;

            final tA = v[0] + minAte(e.l, e.l.shapes[e.si], dk, v[0], pa.f);
            final wt = distTr > 30 ? aPeMinutos(distTr) : 0;
            final w = _primeiraViagem(
                x.l, x.si, dk, pb.f, tA + wt + folgaTrocaMin);
            if (w == null || w[1] - v[1] > tempoIntegracaoMin) continue;

            final tD = w[0] + minAte(x.l, x.l.shapes[x.si], dk, w[0], x.f);
            final wd = aPeMinutos(x.d);
            if (tD <= w[1]) continue;

            final op = OpcaoViagem(
              legs: [
                PernaViagem(
                  l: e.l,
                  si: e.si,
                  k0: e.k,
                  f0: e.f,
                  k1: pa.k,
                  f1: pa.f,
                  t0: v[1],
                  t1: tA,
                  m: v[0],
                ),
                PernaViagem(
                  l: x.l,
                  si: x.si,
                  k0: pb.k,
                  f0: pb.f,
                  k1: x.k,
                  f1: x.f,
                  t0: w[1],
                  t1: tD,
                  m: w[0],
                ),
              ],
              wo: wo,
              wd: wd,
              wt: wt,
              dO: e.d,
              dD: x.d,
              dT: distTr,
              ttu: _noTTU(stopA) && _noTTU(stopB),
              chega: tD + wd,
              sai: v[1] - wo,
            );
            op.custo = calculaCusto(op);
            op.pref = op.custo -
                0.09 * ((math.min(21, math.max(0, w[1] - tA - wt))) ~/ 3);
            if (melhorTroca == null || op.pref < melhorTroca.pref) {
              melhorTroca = op;
            }
          }
        }
        if (melhorTroca != null) ops.add(melhorTroca);
      }
    }

    ops.sort((a, b) => a.custo.compareTo(b.custo));
    final diretas = ops.where((o) => o.legs.length == 1).toList();
    final filtradas = <OpcaoViagem>[];
    final visto = <String, OpcaoViagem>{};

    for (final o in ops) {
      if (o.legs.length == 1) {
        final key = 'd${o.legs[0].l.id}';
        if (visto.containsKey(key)) continue;
        visto[key] = o;
        filtradas.add(o);
      } else {
        if (diretas.any((dir) => dir.custo <= o.custo + 10)) continue;
        final key = 't${o.legs[1].l.id}|${o.legs[1].m}';
        final existente = visto[key];
        if (existente != null) {
          if (existente.legs[0].l.id != o.legs[0].l.id &&
              existente.alt.length < 3 &&
              !existente.alt.any((a) => a['id'] == o.legs[0].l.id)) {
            existente.alt.add({'id': o.legs[0].l.id, 't0': o.legs[0].t0});
          }
          continue;
        }
        visto[key] = o;
        filtradas.add(o);
      }
    }

    filtradas.sort((a, b) {
      final c = a.chega.compareTo(b.chega);
      return c != 0 ? c : a.custo.compareTo(b.custo);
    });

    return ResultadoPlanejamento(
      ops: filtradas.take(4).toList(),
      pertoAPe: dOX <= raioPeMax,
      metrosDireto: arredonda10(dOX),
    );
  }

  // ── Funções do Modo Painel TTU (mantidas intactas do painel-ttu.html) ──
  static double? falta(ShapeLinha sh, double lat, double lon) {
    final p = sh.p;
    if (p.length < 2) return null;
    final c = cumula(sh);
    int b = -1;
    double bd = 1e9;
    for (int i = 0; i < p.length; i++) {
      final d = dist(lat, lon, p[i].latitude, p[i].longitude);
      if (d < bd) {
        bd = d;
        b = i;
      }
    }
    if (bd > 500) return null;
    return c[p.length - 1] - c[b];
  }

  static List<GrupoLinhaOperacional> prepara(DadosTransporteGeral d) {
    const shOffsets = [0, -14, 12, -24, 20, -6, 28];
    final idx = <String, int>{};

    final junta = <String, String>{};
    AppConfig.grupos.forEach((g, lista) {
      for (final id in lista) {
        if (id != g) junta[id] = g;
      }
    });

    final por = <String, GrupoLinhaOperacional>{};

    for (final l in d.linhas) {
      final f = familiaLinha(l);
      idx[f] = idx[f] ?? 0;
      final baseHex = AppConfig.familiaCoresHex[f] ?? '#b07a12';
      l.cor = shadeColor(baseHex, shOffsets[idx[f]! % shOffsets.length]);
      idx[f] = idx[f]! + 1;

      if (l.esc || !l.ttu) continue;

      final g = junta[l.id] ?? l.id;
      final cfg = AppConfig.linhasCfg[g] ?? {};
      final o = por.putIfAbsent(
        g,
        () => GrupoLinhaOperacional(
          id: g,
          ids: [],
          nome: '',
          cor: l.cor,
          cfg: cfg,
          t: {},
          b: {},
        ),
      );
      if (!o.ids.contains(l.id)) o.ids.add(l.id);
      if (g == l.id) {
        o.nome = cfg['nome']?.toString() ?? l.nome;
        o.cor = l.cor;
      }

      for (final s in l.shapes) {
        if (s.off != null) continue;
        final p = s.p;
        double tot = 0, ate = 0, best = 1e9, acc = 0;
        for (int i = 1; i < p.length; i++) {
          tot += dist(p[i - 1].latitude, p[i - 1].longitude, p[i].latitude,
              p[i].longitude);
        }
        for (int i = 0; i < p.length; i++) {
          if (i > 0) {
            acc += dist(p[i - 1].latitude, p[i - 1].longitude, p[i].latitude,
                p[i].longitude);
          }
          final distTtu = dist(p[i].latitude, p[i].longitude,
              AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]);
          if (distTtu < best) {
            best = distTtu;
            ate = acc;
          }
        }
        s.near = best;
        s.off = (best < 180 && tot > 0) ? ((ate / tot) * s.d).round() : null;
      }

      l.dep.forEach((dk, sentidos) {
        for (final sx in ['T', 'B']) {
          final horarios = sentidos[sx] ?? [];
          for (final x in horarios) {
            if (x[1] < 0 || x[1] >= l.shapes.length) continue;
            final sh = l.shapes[x[1]];
            if (espRe.hasMatch(sh.v)) continue;
            final m = x[0] < 180 ? x[0] + 1440 : x[0];
            if (sx == 'B') {
              o.b.putIfAbsent(dk, () => {})[m % 1440] = sh;
              continue;
            }
            if (sh.off == null) continue;
            final vs = (o.cfg['var'] as Map?) ?? {};
            final rot = vs.containsKey(sh.v) ? (vs[sh.v]?.toString() ?? '') : '';
            o.t.putIfAbsent(dk, () => []).add(
                  ViagemProgramada(
                      m: m + sh.off!, ini: m, r: rot, l: l.id, sh: sh),
                );
          }
        }
      });
    }

    final result = por.values.where((o) => o.t.isNotEmpty).toList();
    for (final o in result) {
      for (final lista in o.t.values) {
        lista.sort((p, q) => p.m.compareTo(q.m));
      }
      o.ala = o.cfg['ala']?.toString() ?? '';
      o.dest = o.cfg['dest']?.toString() ?? o.nome;
    }
    return result;
  }

  static List<SituacaoCalculada>? situacaoTtu(
    GrupoLinhaOperacional o,
    String dk,
    List<VeiculoTempoReal> rtVeiculos,
    int rtTimestamp,
  ) {
    final ag = agora();
    final a = o.t[dk] ?? [];
    final prox = a.where((x) => x.m + 2 > ag).toList();
    if (prox.isEmpty) return null;

    final agM = ag.floor() % 1440;
    final noTerm = <VeiculoTempoReal>[];
    final vindo = [];
    final bv = o.b[dk] ?? {};

    for (final x in rtVeiculos) {
      if (!o.ids.contains(x.linhaId) || x.idadeSegundos >= 240) continue;
      final d =
          dist(x.lat, x.lon, AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]);
      final mi = x.minSaida == null ? null : x.minSaida! % 1440;
      final ida =
          x.sentido == '0' || (x.sentido != '1' && mi != null && !bv.containsKey(mi));

      if (d < AppConfig.raioTermPadrao && !(x.velocidade > 8)) {
        if (ida &&
            mi != null &&
            ((agM - mi + 1440) % 1440) < 180 &&
            ((agM - mi + 1440) % 1440) >= 1) {
          continue;
        }
        mem.remove('T|${x.linhaId}|$mi');
        noTerm.add(x);
        continue;
      }
      if (ida) continue;

      final sh = mi != null ? bv[mi] : null;
      final r = sh != null ? falta(sh, x.lat, x.lon) : null;
      final mDist = r ?? (d * 1.35);
      final eta = math.max(
          0.0,
          (mDist / 1000.0 / AppConfig.velKmh * 60.0) -
              (x.idadeSegundos / 60.0));
      final k = 'T|${x.linhaId}|$mi';
      mem[k] = MemoriaGps(
          eta: eta,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          st: mem[k]?.st);
      vindo.add({'x': x, 'k': k, 'eta': math.max(1, eta.round()), 'velho': 0});
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    mem.forEach((k, mObj) {
      final p = k.split('|');
      if (p[0] != 'T' || !o.ids.contains(p[1]) || vindo.any((z) => z['k'] == k)) {
        return;
      }
      final vMin = (nowMs - mObj.timestampMs) / 60000.0;
      if (vMin < memMaxMinutos && mObj.eta - vMin > -2) {
        vindo.add({
          'k': k,
          'eta': math.max(1, (mObj.eta - vMin).round()),
          'velho': vMin.round(),
        });
      }
    });

    vindo.sort((p, q) => (p['eta'] as int).compareTo(q['eta'] as int));

    return prox.take(4).toList().asMap().entries.map((entry) {
      final i = entry.key;
      final x = entry.value;
      final f = (x.m - ag).round();

      if (i < noTerm.length) {
        return SituacaoCalculada(
          x: x,
          c: f <= 0 ? 'saindo' : 'term',
          t: f <= 0 ? 'Saindo' : 'No terminal',
          sub: f > 0 ? 'embarque na plataforma' : '',
        );
      }

      final vIdx = i - noTerm.length;
      final v = (vIdx >= 0 && vIdx < vindo.length) ? vindo[vIdx] : null;
      final velho = (v?['velho'] as int?) ?? 0;
      final nota = velho >= 1 ? ' · último sinal há $velho min' : '';
      final mm = v != null ? mem[v['k']] : null;
      final vEta = v?['eta'] as int?;

      if (v != null && vEta != null && vEta <= 5) {
        if (mm != null) mm.st = 'cheg';
        return SituacaoCalculada(
          x: x,
          c: 'cheg',
          t: 'Chegando',
          sub: '≈ $vEta min para o Terminal$nota',
        );
      }

      if (v != null &&
          vEta != null &&
          (mm?.st == 'atr' ? vEta > f + 3 : vEta > f + 6)) {
        if (mm != null) mm.st = 'atr';
        return SituacaoCalculada(
          x: x,
          c: 'prev',
          t: 'Em ${vEta + 1} min',
          sub: 'saída prevista pelo GPS$nota',
          e: ag + vEta + 1,
          h: ag + vEta + 1,
        );
      }

      if (mm != null) mm.st = 'prog';
      if (f <= 0) {
        return SituacaoCalculada(
            x: x, c: 'saindo', t: 'Agora', sub: 'horário programado');
      }
      return SituacaoCalculada(
        x: x,
        c: 'prog',
        t: f < 60 ? 'Em $f min' : 'Programado',
        sub: v != null
            ? 'ônibus a caminho do Terminal'
            : (rtTimestamp > 0 ? '' : 'sem GPS no momento'),
      );
    }).toList();
  }
}