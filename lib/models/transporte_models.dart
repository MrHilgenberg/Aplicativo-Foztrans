import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class ShapeLinha {
  final int n;
  int main;
  final String v;
  final int d;
  final String sid;
  final List<LatLng> p;
  final Map<String, dynamic>? g; // Perfil medido por GPS (quando presente)

  bool esp = false;
  double? near;
  int? off;
  List<double>? cum;
  List<double>? xPlano;
  List<double>? yPlano;
  List<double>? bbox; // [minX, maxX, minY, maxY]
  List<PontoTrajetoRef>? stCache;

  ShapeLinha({
    required this.n,
    required this.main,
    required this.v,
    required this.d,
    required this.sid,
    required this.p,
    this.g,
  });

  factory ShapeLinha.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['p'] as List<dynamic>? ?? []);
    return ShapeLinha(
      n: (json['n'] as num?)?.toInt() ?? 0,
      main: (json['main'] as num?)?.toInt() ?? 0,
      v: json['v']?.toString() ?? '',
      d: (json['d'] as num?)?.toInt() ?? 0,
      sid: json['sid']?.toString() ?? '',
      g: json['g'] as Map<String, dynamic>?,
      p: rawPoints.map((coord) {
        final c = coord as List<dynamic>;
        return LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble());
      }).toList(),
    );
  }
}

class PontoTrajetoRef {
  final int k; // Índice em D.stops
  final double f; // Fração (0 a 1) no shape
  final int lado; // 0 = mesmo sentido, 1 = sentido oposto
  PontoTrajetoRef({required this.k, required this.f, required this.lado});
}

class LinhaOnibus {
  final String id;
  final String nome;
  final bool esc;
  final bool ttu;
  final List<ShapeLinha> shapes;
  // dep original: {"DU": {"T": [[min, shapeIdx], ...], "B": [...]}}
  final Map<String, Map<String, List<List<int>>>> dep;

  Color cor;
  Color bgc;
  Color ink;

  LinhaOnibus({
    required this.id,
    required this.nome,
    required this.esc,
    required this.ttu,
    required this.shapes,
    required this.dep,
    this.cor = const Color(0xFF1C62B9),
    this.bgc = const Color(0xFF1C62B9),
    this.ink = Colors.white,
  });

  factory LinhaOnibus.fromJson(Map<String, dynamic> json) {
    final depMap = <String, Map<String, List<List<int>>>>{};
    if (json['dep'] is Map) {
      (json['dep'] as Map).forEach((diaKey, sentidosVal) {
        final sMap = <String, List<List<int>>>{};
        if (sentidosVal is Map) {
          sentidosVal.forEach((sentidoKey, listaHorarios) {
            if (listaHorarios is List) {
              sMap[sentidoKey.toString()] = listaHorarios.map((par) {
                final l = par as List;
                return [(l[0] as num).toInt(), (l[1] as num).toInt()];
              }).toList();
            }
          });
        }
        depMap[diaKey.toString()] = sMap;
      });
    }

    return LinhaOnibus(
      id: json['id']?.toString() ?? '',
      nome: json['nome']?.toString() ?? '',
      esc: json['esc'] == true || json['esc'] == 'True',
      ttu: json['ttu'] == true || json['ttu'] == 'True',
      shapes: (json['shapes'] as List<dynamic>? ?? [])
          .map((s) => ShapeLinha.fromJson(s as Map<String, dynamic>))
          .toList(),
      dep: depMap,
    );
  }
}

class PoiLocal {
  final String k;
  final double lat;
  final double lon;
  final String ic;
  final String pt;
  final String es;
  final String en;
  List<String> linhas;

  PoiLocal({
    required this.k,
    required this.lat,
    required this.lon,
    required this.ic,
    required this.pt,
    required this.es,
    required this.en,
    required this.linhas,
  });

  String nomePorIdioma(String lang) {
    if (lang == 'es' && es.isNotEmpty) return es;
    if (lang == 'en' && en.isNotEmpty) return en;
    return pt;
  }

  factory PoiLocal.fromJson(Map<String, dynamic> json) {
    return PoiLocal(
      k: json['k']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      ic: json['ic']?.toString() ?? '◎',
      pt: json['pt']?.toString() ?? '',
      es: json['es']?.toString() ?? '',
      en: json['en']?.toString() ?? '',
      linhas: (json['linhas'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class LinhaSentidoParada {
  final String id;
  final String s; // 'T', 'B' ou ''
  LinhaSentidoParada({required this.id, required this.s});
}

class PontoParada {
  final int index;
  final double lat;
  final double lon;
  final String nome;
  final List<String> linhasRaw;
  final String endereco;
  final List<String> sentidosRaw;
  List<LinhaSentidoParada> linhasAtivas = [];
  double xPlano = 0;
  double yPlano = 0;
  bool? noTtuCache;

  PontoParada({
    required this.index,
    required this.lat,
    required this.lon,
    required this.nome,
    required this.linhasRaw,
    required this.endereco,
    required this.sentidosRaw,
  });

  factory PontoParada.fromArray(int idx, List<dynamic> arr) {
    final lRaw = (arr.length > 3 && arr[3] is List)
        ? (arr[3] as List).map((e) => e.toString()).toList()
        : <String>[];
    final sRaw = (arr.length > 5 && arr[5] is List)
        ? (arr[5] as List).map((e) => e.toString()).toList()
        : <String>[];
    return PontoParada(
      index: idx,
      lat: (arr[0] as num).toDouble(),
      lon: (arr[1] as num).toDouble(),
      nome: arr.length > 2 ? (arr[2]?.toString() ?? '') : '',
      linhasRaw: lRaw,
      endereco: arr.length > 4 ? (arr[4]?.toString() ?? '') : '',
      sentidosRaw: sRaw,
    );
  }

  String get enderecoSemNumero =>
      endereco.replaceFirst(RegExp(r',\s*\d[\d\s\-–]*$'), '');

  String tituloExibicao([String padrao = 'Ponto de parada']) {
    if (nome.isNotEmpty) return nome;
    final sNum = enderecoSemNumero;
    if (sNum.isNotEmpty) return sNum;
    return padrao;
  }
}

class VeiculoTempoReal {
  final String prefixo;
  final double lat;
  final double lon;
  final String linhaId;
  final String sentido; // '0' = IDA (T), '1' = VOLTA (B)
  final int? minSaida;
  final int idadeSegundos;
  final double velocidade;

  VeiculoTempoReal({
    required this.prefixo,
    required this.lat,
    required this.lon,
    required this.linhaId,
    required this.sentido,
    required this.minSaida,
    required this.idadeSegundos,
    required this.velocidade,
  });

  factory VeiculoTempoReal.fromArray(List<dynamic> x) {
    return VeiculoTempoReal(
      prefixo: x.isNotEmpty ? x[0].toString() : '',
      lat: x.length > 1 ? (x[1] as num).toDouble() : 0.0,
      lon: x.length > 2 ? (x[2] as num).toDouble() : 0.0,
      linhaId: x.length > 3 ? x[3].toString() : '',
      sentido: x.length > 4 && x[4] != null ? x[4].toString() : '',
      minSaida: x.length > 5 && x[5] != null ? (x[5] as num).toInt() : null,
      idadeSegundos: x.length > 6 && x[6] != null ? (x[6] as num).toInt() : 0,
      velocidade: x.length > 7 && x[7] != null ? (x[7] as num).toDouble() : 0.0,
    );
  }
}

class EnderecoBuscaResult {
  final String nome;
  final String sub;
  final double lat;
  final double lon;
  final String icone;
  final bool ibge;

  EnderecoBuscaResult({
    required this.nome,
    this.sub = '',
    required this.lat,
    required this.lon,
    this.icone = '◎',
    this.ibge = false,
  });
}

class DadosTransporteGeral {
  final List<LinhaOnibus> linhas;
  final List<PoiLocal> poi;
  final List<PontoParada> stops;
  final Map<String, dynamic> especiais;
  final Map<String, dynamic> feriados;
  final Map<String, dynamic> avisos;
  final List avisosLista;
  final Map<String, dynamic> siglas;
  final String versao;
  final String fonte;

  DadosTransporteGeral({
    required this.linhas,
    required this.poi,
    required this.stops,
    required this.especiais,
    required this.feriados,
    required this.avisos,
    required this.avisosLista,
    required this.siglas,
    this.versao = '',
    this.fonte = 'drive',
  });

  factory DadosTransporteGeral.fromJson(Map<String, dynamic> json,
      {String fonte = 'drive'}) {
    final stopsList = <PontoParada>[];
    final rawStops = json['stops'] as List<dynamic>? ?? [];
    for (int i = 0; i < rawStops.length; i++) {
      if (rawStops[i] is List) {
        stopsList.add(PontoParada.fromArray(i, rawStops[i] as List<dynamic>));
      }
    }

    return DadosTransporteGeral(
      linhas: (json['linhas'] as List<dynamic>? ?? [])
          .map((e) => LinhaOnibus.fromJson(e as Map<String, dynamic>))
          .toList(),
      poi: (json['poi'] as List<dynamic>? ?? [])
          .map((e) => PoiLocal.fromJson(e as Map<String, dynamic>))
          .toList(),
      stops: stopsList,
      especiais: (json['especiais'] as Map<String, dynamic>?) ?? {},
      feriados: (json['feriados'] as Map<String, dynamic>?) ?? {},
      avisos: (json['avisos'] as Map<String, dynamic>?) ?? {},
      avisosLista: (json['avisosLista'] as List<dynamic>? ?? [])
          .whereType()
          .toList(),
      siglas: (json['siglas'] as Map<String, dynamic>?) ?? {},
      versao: json['versao']?.toString() ?? '',
      fonte: fonte,
    );
  }
}