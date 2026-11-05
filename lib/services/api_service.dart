import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/transporte_models.dart';
import '../utils/motor_horarios.dart';

class ResultadoTempoReal {
  final int t;
  final List<VeiculoTempoReal> v;
  ResultadoTempoReal({required this.t, required this.v});
}

class RotaCaminhada {
  final int metros;
  final List<LatLng> pontos;
  RotaCaminhada({required this.metros, required this.pontos});
}

class ApiService {
  static const String _cacheKey = 'mapa_dados';
  static const String _ruasCacheKey = 'fz_ruas_1';
  static const String _photonUrl = 'https://photon.komoot.io/api/';
  static const String _fozBbox = '-54.66,-25.72,-54.40,-25.36';
  static const String _rotaPeUrl =
      'https://routing.openstreetmap.de/routed-foot/route/v1/foot/';

  static final Map<String, RotaCaminhada> _cacheRotas = {};
  static Map<String, dynamic>? _indiceIbge;
  static final Map<int, List<dynamic>> _numerosIbgeCache = {};

  /// Carrega os dados salvos no aparelho
  Future<DadosTransporteGeral?> carregarCacheLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['linhas'] != null) {
          return DadosTransporteGeral.fromJson(decoded, fonte: 'cache');
        }
      }
    } catch (_) {}
    return null;
  }

  /// Baixa dados atualizados do Google Apps Script e salva no cache local
  Future<DadosTransporteGeral?> baixaDados() async {
    try {
      final uri = Uri.parse(AppConfig.dadosUrl);
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        if (decoded['linhas'] != null) {
          final dados = DadosTransporteGeral.fromJson(decoded, fonte: 'drive');
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cacheKey, resp.body);
          } catch (_) {}
          return dados;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Busca posições GPS no Cloudflare Worker (com fallback para o Apps Script)
  Future<ResultadoTempoReal> baixaRT(List<String> linhasIds) async {
    if (linhasIds.isEmpty) return ResultadoTempoReal(t: 0, v: []);

    final lotes = <List<String>>[];
    for (int i = 0; i < linhasIds.length; i += 12) {
      final fim =
          (i + 12 < linhasIds.length) ? i + 12 : linhasIds.length;
      lotes.add(linhasIds.sublist(i, fim));
    }

    final baseUrl = AppConfig.rtUrl.endsWith('/')
        ? AppConfig.rtUrl
        : '${AppConfig.rtUrl}/';

    final futures = lotes.map((lote) async {
      final param = Uri.encodeComponent(lote.join(','));
      try {
        final uri = Uri.parse('$baseUrl?onibus=1&linha=$param');
        final resp = await http
            .get(uri)
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          if (j['t'] != null) return j;
        }
      } catch (_) {}
      // Fallback para o Apps Script se o Worker falhar
      try {
        final uriFallback =
            Uri.parse('${AppConfig.dadosUrl}?onibus=1&linha=$param');
        final resp = await http
            .get(uriFallback)
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
      return null;
    });

    final resultados = await Future.wait(futures);
    int maiorT = 0;
    final todosVeiculos = <VeiculoTempoReal>[];

    for (final r in resultados) {
      if (r == null || r['t'] == null) continue;
      final tVal = (r['t'] as num?)?.toInt() ?? 0;
      if (tVal > maiorT) maiorT = tVal;
      final vLista = r['v'] as List<dynamic>? ?? [];
      for (final item in vLista) {
        if (item is List) {
          todosVeiculos.add(VeiculoTempoReal.fromArray(item));
        }
      }
    }

    return ResultadoTempoReal(t: maiorT, v: todosVeiculos);
  }

  /// Busca endereços em Foz do Iguaçu combinando IBGE Censo 2022 (se tiver número) + Photon OSM
  Future<List<EnderecoBuscaResult>> buscarEnderecos(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];

    final futures = await Future.wait([
      _buscarNumeroIbge(q),
      _buscarPhoton(q),
    ]);

    final doIbge = futures[0];
    final doPhoton = futures[1];

    final resultado = <EnderecoBuscaResult>[...doIbge];
    for (final r in doPhoton) {
      final duplicado = doIbge
          .any((x) => MotorHorarios.dist(x.lat, x.lon, r.lat, r.lon) < 40);
      if (!duplicado) resultado.add(r);
    }
    return resultado.take(7).toList();
  }

  Future<List<EnderecoBuscaResult>> _buscarPhoton(String q) async {
    try {
      final uri = Uri.parse(
          '$_photonUrl?q=${Uri.encodeComponent(q)}&limit=12&bbox=$_fozBbox&lat=-25.53&lon=-54.57');
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = j['features'] as List<dynamic>? ?? [];
      final vistos = <String>{};
      final out = <EnderecoBuscaResult>[];

      for (final f in features) {
        final prop = (f['properties'] as Map<String, dynamic>?) ?? {};
        final geom = (f['geometry'] as Map<String, dynamic>?) ?? {};
        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;
        if (prop['countrycode'] != null && prop['countrycode'] != 'BR') {
          continue;
        }
        if (prop['osm_value'] == 'bus_stop') continue;

        final street = prop['street']?.toString() ?? '';
        final hNum = prop['housenumber']?.toString() ?? '';
        final rua = street.isNotEmpty
            ? '$street${hNum.isNotEmpty ? ', $hNum' : ''}'
            : '';
        final nome = prop['name']?.toString() ?? rua;
        if (nome.isEmpty) continue;

        final partesSub = <String>[];
        if (prop['name'] != null && rua.isNotEmpty) partesSub.add(rua);
        final bairro = prop['district'] ?? prop['locality'] ?? prop['suburb'];
        if (bairro != null && bairro.toString().isNotEmpty) {
          partesSub.add(bairro.toString());
        }
        final sub = partesSub.join(' · ');
        final chave = '${nome.toLowerCase()}|${sub.toLowerCase()}';
        if (vistos.contains(chave)) continue;
        vistos.add(chave);

        out.add(EnderecoBuscaResult(
          nome: nome,
          sub: sub,
          lat: (coords[1] as num).toDouble(),
          lon: (coords[0] as num).toDouble(),
        ));
      }
      return out.take(6).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<EnderecoBuscaResult>> _buscarNumeroIbge(String q) async {
    final m = RegExp(
            r'^(.*?[a-zà-ú].*?)[\s,;.-]+(?:n[ºo°.]?\s*)?(\d{1,6})\s*[a-z]?\s*$',
            caseSensitive: false)
        .firstMatch(q);
    if (m == null) return [];
    final nomeRuaBusca = m.group(1)!;
    final numAlvo = int.tryParse(m.group(2)!) ?? 0;
    if (numAlvo <= 0) return [];

    try {
      final indice = await _carregarIndiceRuasIbge();
      if (indice == null) return [];
      final ruas = (indice['ruas'] as List<dynamic>?) ?? [];
      final bairros = (indice['bairros'] as List<dynamic>?) ?? [];

      final tokensBusca = _tokensEndereco(nomeRuaBusca);
      if (tokensBusca.isEmpty) return [];

      final candidatas = <int>[];
      for (int i = 0; i < ruas.length; i++) {
        final rNome = ruas[i].toString();
        final rTokens = _tokensEndereco(rNome);
        if (tokensBusca.every((tb) => rTokens.any((rt) => rt.startsWith(tb)))) {
          candidatas.add(i);
          if (candidatas.length >= 4) break;
        }
      }
      if (candidatas.isEmpty) return [];

      final faltam =
          candidatas.where((id) => !_numerosIbgeCache.containsKey(id)).toList();
      if (faltam.isNotEmpty) {
        final uri =
            Uri.parse('${AppConfig.dadosUrl}?rua=${faltam.join(',')}');
        final resp = await http.get(uri).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          final rMap = (j['r'] as Map<String, dynamic>?) ?? {};
          rMap.forEach((k, v) {
            final idx = int.tryParse(k);
            if (idx != null && v is List) _numerosIbgeCache[idx] = v;
          });
        }
      }

      final exatos = <EnderecoBuscaResult>[];
      final aproximados = <EnderecoBuscaResult>[];

      for (final rIdx in candidatas) {
        final arr = _numerosIbgeCache[rIdx];
        if (arr == null || arr.length < 6) continue;
        final la0 = (arr[0] as num).toDouble();
        final lo0 = (arr[1] as num).toDouble();
        final nomeFormatado = MotorHorarios.cap(ruas[rIdx].toString().toLowerCase());

        double menorDif = 1e9;
        EnderecoBuscaResult? melhorAprox;

        for (int k = 2; k < arr.length; k += 4) {
          final n = (arr[k] as num).toInt();
          final lat = (la0 + (arr[k + 1] as num).toDouble()) / 1e5;
          final lon = (lo0 + (arr[k + 2] as num).toDouble()) / 1e5;
          final bIdx = (arr[k + 3] as num).toInt();
          final bairro = (bIdx >= 0 && bIdx < bairros.length)
              ? MotorHorarios.cap(bairros[bIdx].toString().toLowerCase())
              : '';

          if (n == numAlvo) {
            exatos.add(EnderecoBuscaResult(
              nome: '$nomeFormatado, $n',
              sub: bairro,
              lat: lat,
              lon: lon,
              ibge: true,
            ));
          } else {
            final dif = (n - numAlvo).abs() + ((n - numAlvo) % 2 != 0 ? 0.5 : 0.0);
            if (dif < menorDif && (n - numAlvo).abs() <= 100) {
              menorDif = dif;
              melhorAprox = EnderecoBuscaResult(
                nome: '$nomeFormatado, $numAlvo',
                sub:
                    'número mais próximo cadastrado: $n${bairro.isNotEmpty ? ' · $bairro' : ''}',
                lat: lat,
                lon: lon,
                ibge: true,
              );
            }
          }
        }
        if (exatos.isEmpty && melhorAprox != null) {
          aproximados.add(melhorAprox);
        }
      }
      return (exatos.isNotEmpty ? exatos : aproximados).take(4).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> _carregarIndiceRuasIbge() async {
    if (_indiceIbge != null) return _indiceIbge;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_ruasCacheKey);
      if (cached != null) {
        final j = jsonDecode(cached) as Map<String, dynamic>;
        final em = (j['em'] as num?)?.toInt() ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - em < 7 * 86400000) {
          _indiceIbge = j;
          return j;
        }
      }
      final uri = Uri.parse('${AppConfig.dadosUrl}?enderecos=1');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        if (j['ruas'] is List && (j['ruas'] as List).isNotEmpty) {
          j['em'] = DateTime.now().millisecondsSinceEpoch;
          await prefs.setString(_ruasCacheKey, jsonEncode(j));
          _indiceIbge = j;
          return j;
        }
      }
    } catch (_) {}
    return null;
  }

  List<String> _tokensEndereco(String t) {
    const ignorar = {
      'DE', 'DA', 'DO', 'DOS', 'DAS', 'E', 'R', 'RUA', 'AV', 'AVENIDA', 'TV', 'TRAVESSA', 'AL', 'ALAMEDA'
    };
    final semAc = MotorHorarios.semAcento(t);
    return semAc
        .split(RegExp(r'[^A-Z0-9]+'))
        .where((w) => w.isNotEmpty && !ignorar.contains(w))
        .toList();
  }

  /// Calcula rota a pé pelas ruas via FOSSGIS OSRM aplicando o filtro `atalho` (canteiro central)
  Future<RotaCaminhada?> rotaPe(LatLng a, LatLng c) async {
    final key =
        '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)};${c.latitude.toStringAsFixed(5)},${c.longitude.toStringAsFixed(5)}';
    if (_cacheRotas.containsKey(key)) return _cacheRotas[key];

    final reta = MotorHorarios.dist(a.latitude, a.longitude, c.latitude, c.longitude);
    try {
      final url =
          '$_rotaPeUrl${a.longitude.toStringAsFixed(5)},${a.latitude.toStringAsFixed(5)};${c.longitude.toStringAsFixed(5)},${c.latitude.toStringAsFixed(5)}?overview=full&geometries=geojson';
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        if (j['code'] == 'Ok' &&
            j['routes'] is List &&
            (j['routes'] as List).isNotEmpty) {
          final route = j['routes'][0] as Map<String, dynamic>;
          final coords =
              (route['geometry']?['coordinates'] as List<dynamic>?) ?? [];
          if (coords.length >= 2) {
            final bruta = coords.map((v) {
              final l = v as List<dynamic>;
              return LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble());
            }).toList();

            var refinada = _atalho([a, ...bruta, c]);
            refinada = _atalho(refinada.reversed.toList()).reversed.toList();

            double m = 0;
            for (int i = 1; i < refinada.length; i++) {
              m += MotorHorarios.dist(
                refinada[i - 1].latitude,
                refinada[i - 1].longitude,
                refinada[i].latitude,
                refinada[i].longitude,
              );
            }
            if (m <= reta * 8 + 1500) {
              final res =
                  RotaCaminhada(metros: m.round(), pontos: refinada);
              _cacheRotas[key] = res;
              return res;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  List<LatLng> _atalho(List<LatLng> p) {
    final d = <LatLng>[];
    for (int i = 0; i < p.length; i++) {
      if (i > 0) {
        final a = p[i - 1], b = p[i];
        final distSeg =
            MotorHorarios.dist(a.latitude, a.longitude, b.latitude, b.longitude);
        final n = (distSeg / 30.0).floor();
        for (int k = 1; k <= n; k++) {
          final t = k / (n + 1);
          d.add(LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ));
        }
      }
      d.add(p[i]);
    }
    final n = d.length;
    final fim = d[n - 1];
    final ate = <double>[0.0];
    for (int i = 1; i < n; i++) {
      ate.add(ate[i - 1] +
          MotorHorarios.dist(
              d[i - 1].latitude, d[i - 1].longitude, d[i].latitude, d[i].longitude));
    }
    final tot = ate[n - 1];
    int best = -1;
    double bc = tot - 150.0;
    for (int i = 0; i < n - 1; i++) {
      final ds = MotorHorarios.dist(
          d[i].latitude, d[i].longitude, fim.latitude, fim.longitude);
      if (ds > 100 || tot - ate[i] <= 2.5 * ds + 80) continue;
      final c = ate[i] + 1.3 * ds;
      if (c < bc) {
        bc = c;
        best = i;
      }
    }
    return best < 0 ? p : [...d.sublist(0, best + 1), fim];
  }
}