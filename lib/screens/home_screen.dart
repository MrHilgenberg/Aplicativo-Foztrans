import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../models/transporte_models.dart';
import '../services/api_service.dart';
import '../utils/motor_horarios.dart';
import 'painel_ttu_screen.dart';

class HomeScreen extends StatefulWidget {
  final DadosTransporteGeral dadosIniciais;
  const HomeScreen({super.key, required this.dadosIniciais});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _origemController = TextEditingController();

  late DadosTransporteGeral _d;
  String _lang = 'pt';
  String _abaFamilia = 'all'; // 'all', 'f0', 'f1', 'f2', 'f3'
  bool _satelite = false;
  double _zoomAtual = 12.2;

  // Estado de seleção
  String? _linhaSelId;
  String _diaSel = 'DU';
  String _sentidoSel = 'T';
  int? _viagemSelIdx;
  bool _verPassados = false;
  LatLng? _trechoSel;

  // Estado de localização e Destino / Planejador (A -> B)
  LatLng? _minhaLoc;
  LatLng? _origemManual;
  String _origemNome = '';
  ({String nome, double lat, double lon, bool eu})? _destino;
  ResultadoPlanejamento? _plano;
  int? _opcaoPlanoSel;
  List<LatLng>? _rotaPeOrigemPts;
  List<LatLng>? _rotaPeDestinoPts;

  // Modo escolher ponto no mapa com alfinete central
  bool _escolhendoNoMapa = false;
  String _alvoAlfinete = 'para'; // 'de' ou 'para'

  // Busca de endereços (Photon + IBGE)
  Timer? _debounceGeo;
  bool _buscandoGeo = false;
  List<EnderecoBuscaResult> _resultadosGeo = [];

  // Ônibus em tempo real
  List<VeiculoTempoReal> _veiculosRt = [];
  Timer? _timerRt;

  @override
  void initState() {
    super.initState();
    _d = widget.dadosIniciais;
    MotorHorarios.inicializarDadosMapa(_d);
    _diaSel = MotorHorarios.tipoDia(_d);
    _atualizarDadosEmSegundoPlano();
    _timerRt = Timer.periodic(const Duration(seconds: 30), (_) {
      _atualizarPosicoesRt();
    });
  }

  @override
  void dispose() {
    _debounceGeo?.cancel();
    _timerRt?.cancel();
    _searchController.dispose();
    _origemController.dispose();
    super.dispose();
  }

  List<LinhaOnibus> get _linhasPublicas =>
      _d.linhas.where((l) => !l.esc).toList();

  LinhaOnibus? _porId(String? id) {
    if (id == null) return null;
    return _linhasPublicas.where((l) => l.id == id).firstOrNull;
  }

  Future<void> _atualizarDadosEmSegundoPlano() async {
    final novo = await _api.baixaDados();
    if (novo != null && mounted) {
      setState(() {
        _d = novo;
        MotorHorarios.inicializarDadosMapa(_d);
      });
    }
    _atualizarPosicoesRt();
  }

  Future<void> _atualizarPosicoesRt() async {
    final ids = <String>{};
    if (_linhaSelId != null) {
      ids.add(_linhaSelId!);
    } else if (_plano != null && _plano!.ops.isNotEmpty) {
      for (final op in _plano!.ops) {
        for (final leg in op.legs) {
          ids.add(leg.l.id);
        }
      }
    }
    if (ids.isEmpty) return;
    final res = await _api.baixaRT(ids.toList());
    if (mounted) {
      setState(() => _veiculosRt = res.v);
    }
  }

  Future<void> _obterMinhaLocalizacao({bool abrirPertoDeMim = false}) async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão de localização negada.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _minhaLoc = ll;
        if (_destino != null && !_destino!.eu) {
          _origemManual = null;
          _origemNome = 'Sua localização';
          _origemController.text = _origemNome;
          _recalcularPlano();
        } else if (abrirPertoDeMim) {
          _definirDestino(
              nome: 'Perto de você',
              lat: ll.latitude,
              lon: ll.longitude,
              eu: true);
        }
      });
      _mapController.move(ll, 15.5);
    } catch (_) {}
  }

  void _selecionarLinha(String? id,
      {bool manterTrecho = false, String? sentIni}) {
    setState(() {
      _linhaSelId = id;
      _viagemSelIdx = null;
      _verPassados = false;
      if (!manterTrecho) _trechoSel = null;
      if (id != null) {
        final l = _porId(id)!;
        final hk = MotorHorarios.tipoDia(_d);
        _diaSel = l.dep.containsKey(hk) ? hk : (l.dep.keys.firstOrNull ?? 'DU');
        final sDisp = ['T', 'B']
            .where((k) => (l.dep[_diaSel]?[k]?.isNotEmpty ?? false))
            .toList();
        if (sentIni != null && sDisp.contains(sentIni)) {
          _sentidoSel = sentIni;
        } else if (sDisp.isNotEmpty && !sDisp.contains(_sentidoSel)) {
          _sentidoSel = sDisp.first;
        }
        final pts = <LatLng>[];
        for (final s in l.shapes.where((x) => x.main == 1)) {
          pts.addAll(s.p);
        }
        if (pts.length >= 2 && _trechoSel == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(pts),
                padding: const EdgeInsets.all(40),
                maxZoom: 16.0,
              ),
            );
          });
        }
      }
    });
    _atualizarPosicoesRt();
  }

  void _definirDestino({
    required String nome,
    required double lat,
    required double lon,
    bool eu = false,
  }) {
    setState(() {
      _linhaSelId = null;
      _viagemSelIdx = null;
      _trechoSel = null;
      _destino = (nome: nome, lat: lat, lon: lon, eu: eu);
      _opcaoPlanoSel = null;
      _rotaPeOrigemPts = null;
      _rotaPeDestinoPts = null;
      if (!eu) {
        _recalcularPlano();
      } else {
        _plano = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(LatLng(lat, lon), 15.0);
    });
    _atualizarPosicoesRt();
  }

  void _recalcularPlano() {
    if (_destino == null || _destino!.eu) return;
    final orig = _origemManual ?? _minhaLoc;
    if (orig == null) {
      setState(() => _plano = null);
      return;
    }
    final res = MotorHorarios.planejarViagem(
      _d,
      orig,
      LatLng(_destino!.lat, _destino!.lon),
    );
    setState(() {
      _plano = res;
      _opcaoPlanoSel = res.ops.isNotEmpty ? 0 : null;
    });
    if (res.ops.isNotEmpty) {
      _carregarCaminhadasReais(res.ops.first);
    }
  }

  Future<void> _carregarCaminhadasReais(OpcaoViagem op) async {
    final orig = _origemManual ?? _minhaLoc;
    if (orig == null || _destino == null) return;
    final p0 = _d.stops[op.legs.first.k0];
    final pFim = _d.stops[op.legs.last.k1];

    final rO = await _api.rotaPe(orig, LatLng(p0.lat, p0.lon));
    final rD = await _api.rotaPe(
        LatLng(pFim.lat, pFim.lon), LatLng(_destino!.lat, _destino!.lon));

    if (!mounted) return;
    setState(() {
      if (rO != null) {
        op.rO = rO.metros;
        _rotaPeOrigemPts = rO.pontos;
      }
      if (rD != null) {
        op.rD = rD.metros;
        _rotaPeDestinoPts = rD.pontos;
      }
    });
  }

  void _aoTocarNoMapa(TapPosition tapPos, LatLng ll) {
    if (_escolhendoNoMapa) return;
    final lSel = _porId(_linhaSelId);
    if (lSel != null) {
      double menorD = 1e9;
      LatLng? ptMaisPerto;
      for (final s in lSel.shapes) {
        final r = MotorHorarios.aoLongo(s, ll.latitude, ll.longitude);
        if (r.d < menorD) {
          menorD = r.d;
          ptMaisPerto = LatLng(r.lat, r.lon);
        }
      }
      if (menorD <= 80 && ptMaisPerto != null) {
        setState(() {
          _trechoSel = ptMaisPerto;
          _viagemSelIdx = null;
        });
      }
      return;
    }

    double menorD = 1e9;
    LatLng? ptMaisPerto;
    LinhaOnibus? linhaMaisPerto;
    for (final l in _linhasPublicas) {
      for (final s in l.shapes.where((x) => x.main == 1)) {
        final r = MotorHorarios.aoLongo(s, ll.latitude, ll.longitude);
        if (r.d < menorD) {
          menorD = r.d;
          ptMaisPerto = LatLng(r.lat, r.lon);
          linhaMaisPerto = l;
        }
      }
    }
    if (menorD <= 60 && ptMaisPerto != null && linhaMaisPerto != null) {
      setState(() => _trechoSel = ptMaisPerto);
      _selecionarLinha(linhaMaisPerto.id, manterTrecho: true);
    }
  }

  void _aoDigitarBusca(String valor) {
    _debounceGeo?.cancel();
    setState(() {
      if (_linhaSelId != null || _destino != null) {
        _linhaSelId = null;
        _destino = null;
        _plano = null;
      }
    });
    final v = valor.trim();
    if (v.length < 3 || RegExp(r'^\d+\s?\w?$').hasMatch(v)) {
      setState(() {
        _buscandoGeo = false;
        _resultadosGeo = [];
      });
      return;
    }
    setState(() => _buscandoGeo = true);
    _debounceGeo = Timer(const Duration(milliseconds: 550), () async {
      final res = await _api.buscarEnderecos(v);
      if (mounted && _searchController.text.trim() == v) {
        setState(() {
          _buscandoGeo = false;
          _resultadosGeo = res;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lSel = _porId(_linhaSelId);

    return Scaffold(
      body: Stack(
        children: [
          // 1. MAPA INTERATIVO
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-25.5326, -54.5750),
              initialZoom: _zoomAtual,
              minZoom: 10.0,
              maxZoom: 19.0,
              onPositionChanged: (pos, _) {
                final z = pos.zoom;
                if (z != null && (z - _zoomAtual).abs() > 0.25) {
                  setState(() => _zoomAtual = z);
                }
              },
              onTap: _aoTocarNoMapa,
            ),
            children: [
              TileLayer(
                urlTemplate: _satelite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'br.gov.pr.foz.foztrans.mobifoz',
                maxNativeZoom: 19,
              ),
              PolylineLayer(polylines: _construirPolilinhas(lSel, isDark)),
              if (_zoomAtual >= 14.5 || (lSel != null && _zoomAtual >= 13.0))
                MarkerLayer(markers: _construirMarkersParadas(lSel)),
              MarkerLayer(markers: _construirMarkersPois()),
              MarkerLayer(markers: _construirMarkersEspeciais(lSel)),
            ],
          ),

          // Alfinete central ao escolher Partida/Destino no mapa
          if (_escolhendoNoMapa)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 34),
                  child: Icon(
                    Icons.location_on,
                    size: 44,
                    color: Color(0xFFF07800),
                  ),
                ),
              ),
            ),

          if (_escolhendoNoMapa)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: Material(
                color: AppConfig.brandLight,
                borderRadius: BorderRadius.circular(12),
                elevation: 6,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _alvoAlfinete == 'para'
                              ? 'Mova o mapa até o alfinete ficar no seu destino.'
                              : 'Mova o mapa até o alfinete ficar no local de partida.',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.accentLight,
                          foregroundColor: const Color(0xFF1A0F00),
                        ),
                        onPressed: () {
                          final c = _mapController.camera.center;
                          setState(() => _escolhendoNoMapa = false);
                          if (_alvoAlfinete == 'para') {
                            _definirDestino(
                              nome: 'Destino escolhido no mapa',
                              lat: c.latitude,
                              lon: c.longitude,
                            );
                          } else {
                            setState(() {
                              _origemManual = c;
                              _origemNome = 'Ponto escolhido no mapa';
                              _origemController.text = _origemNome;
                            });
                            _recalcularPlano();
                          }
                        },
                        child: Text(
                          _alvoAlfinete == 'para' ? 'Ir para cá' : 'Sair daqui',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _escolhendoNoMapa = false),
                        child: const Text('Cancelar',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Botões flutuantes no canto superior direito
          if (!_escolhendoNoMapa)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _BotaoMapa(
                    icone: Icons.my_location,
                    rotulo: 'Onde estou',
                    onTap: () => _obterMinhaLocalizacao(abrirPertoDeMim: true),
                  ),
                  const SizedBox(height: 6),
                  _BotaoMapa(
                    icone: _satelite ? Icons.map : Icons.satellite_alt,
                    rotulo: _satelite ? 'Mapa: Satélite' : 'Mapa: Ruas',
                    onTap: () => setState(() => _satelite = !_satelite),
                  ),
                  const SizedBox(height: 6),
                  _BotaoMapa(
                    icone: Icons.tv,
                    rotulo: 'Painel TTU',
                    destaque: true,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PainelTtuScreen(dados: _d),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // 2. FOLHA INFERIOR RETRÁTIL
          if (!_escolhendoNoMapa)
            DraggableScrollableSheet(
              initialChildSize: 0.52,
              minChildSize: 0.14,
              maxChildSize: 0.90,
              snap: true,
              snapSizes: const [0.14, 0.52, 0.90],
              builder: (context, scrollController) {
                return Material(
                  color: isDark ? AppConfig.bgDark : AppConfig.bgLight,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  elevation: 12,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Puxador (sheetbar)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        color: (lSel == null && _destino == null)
                            ? (isDark
                                ? AppConfig.brandDark
                                : AppConfig.brandLight)
                            : Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: (lSel == null && _destino == null)
                                  ? Colors.white54
                                  : Colors.grey.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      if (lSel == null && _destino == null)
                        _construirCabecalhoBusca(isDark)
                      else if (lSel != null)
                        _construirBarraLinha(lSel, isDark)
                      else if (_destino != null)
                        _construirBarraDestino(isDark),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            if (lSel != null)
                              _construirDetalheLinha(lSel, isDark)
                            else if (_destino != null)
                              _construirPainelDestino(isDark)
                            else
                              _construirListaInicial(isDark),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Camadas do Mapa ──
  List<Polyline> _construirPolilinhas(LinhaOnibus? lSel, bool isDark) {
    final polylines = <Polyline>[];

    if (lSel == null &&
        _destino != null &&
        _plano != null &&
        _opcaoPlanoSel != null &&
        _opcaoPlanoSel! < _plano!.ops.length) {
      final op = _plano!.ops[_opcaoPlanoSel!];
      final orig = _origemManual ?? _minhaLoc;
      if (orig != null) {
        final p0 = _d.stops[op.legs.first.k0];
        final ptsOrig = _rotaPeOrigemPts ?? [orig, LatLng(p0.lat, p0.lon)];
        if (ptsOrig.length >= 2) {
          polylines.add(
            Polyline(
              points: ptsOrig,
              color: isDark ? Colors.white : const Color(0xFF14212B),
              strokeWidth: 3.5,
              pattern: StrokePattern.dashed(segments: const [8, 6]),
            ),
          );
        }
      }
      for (int i = 0; i < op.legs.length; i++) {
        final leg = op.legs[i];
        final pts =
            MotorHorarios.fatia(leg.l.shapes[leg.si], leg.f0, leg.f1);
        if (pts.length >= 2) {
          polylines.add(
              Polyline(points: pts, color: Colors.white, strokeWidth: 10.0));
          polylines.add(
              Polyline(points: pts, color: leg.l.cor, strokeWidth: 6.5));
        }
      }
      final pFim = _d.stops[op.legs.last.k1];
      final ptsDest = _rotaPeDestinoPts ??
          [
            LatLng(pFim.lat, pFim.lon),
            LatLng(_destino!.lat, _destino!.lon)
          ];
      if (ptsDest.length >= 2) {
        polylines.add(
          Polyline(
            points: ptsDest,
            color: isDark ? Colors.white : const Color(0xFF14212B),
            strokeWidth: 3.5,
            pattern: StrokePattern.dashed(segments: const [8, 6]),
          ),
        );
      }
      return polylines;
    }

    if (lSel != null) {
      final pares = (lSel.dep[_diaSel] ?? {})[_sentidoSel] ?? [];
      if (_viagemSelIdx != null && _viagemSelIdx! < pares.length) {
        final si = pares[_viagemSelIdx!][1];
        final pts = lSel.shapes[si].p;
        if (pts.length >= 2) {
          polylines.add(
              Polyline(points: pts, color: Colors.white, strokeWidth: 11.0));
          polylines
              .add(Polyline(points: pts, color: lSel.cor, strokeWidth: 7.0));
        }
        return polylines;
      }

      final shapesSentido = pares.map((x) => x[1]).toSet();
      for (int i = 0; i < lSel.shapes.length; i++) {
        if (!shapesSentido.contains(i)) continue;
        final s = lSel.shapes[i];
        if (s.p.length < 2) continue;
        final isMain = s.main == 1;
        polylines.add(Polyline(
          points: s.p,
          color: Colors.white,
          strokeWidth: isMain ? 9.0 : 5.5,
        ));
        polylines.add(Polyline(
          points: s.p,
          color: lSel.cor,
          strokeWidth: isMain ? 5.5 : 3.5,
          pattern: isMain
              ? const StrokePattern.solid()
              : StrokePattern.dashed(segments: const [10, 7]),
        ));
      }
      return polylines;
    }

    for (final l in _linhasPublicas) {
      for (final s in l.shapes.where((x) => x.main == 1)) {
        if (s.p.length < 2) continue;
        polylines.add(Polyline(
          points: s.p,
          color: Colors.white.withOpacity(0.85),
          strokeWidth: 5.5,
        ));
        polylines.add(Polyline(
          points: s.p,
          color: l.cor.withOpacity(0.9),
          strokeWidth: 3.2,
        ));
      }
    }
    return polylines;
  }

  List<Marker> _construirMarkersParadas(LinhaOnibus? lSel) {
    final markers = <Marker>[];
    final stopsFiltrados = lSel != null
        ? _d.stops.where((s) => s.linhasAtivas
            .any((o) => o.id == lSel.id && (o.s.isEmpty || o.s == _sentidoSel)))
        : _d.stops.where((s) => s.linhasAtivas.isNotEmpty);

    for (final s in stopsFiltrados) {
      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: 22,
          height: 22,
          child: GestureDetector(
            onTap: () => _abrirModalParada(s),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: lSel != null ? lSel.cor : AppConfig.brandLight,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.directions_bus,
                size: 13,
                color: lSel != null ? lSel.cor : AppConfig.brandLight,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Marker> _construirMarkersPois() {
    return _d.poi.map((p) {
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => _definirDestino(
            nome: p.nomePorIdioma(_lang),
            lat: p.lat,
            lon: p.lon,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppConfig.brandLight,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4)
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              p.ic,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _construirMarkersEspeciais(LinhaOnibus? lSel) {
    final m = <Marker>[];
    if (_minhaLoc != null) {
      m.add(
        Marker(
          point: _minhaLoc!,
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              color: AppConfig.accentLight,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    if (_trechoSel != null) {
      m.add(
        Marker(
          point: _trechoSel!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: AppConfig.accentLight,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    if (_origemManual != null) {
      m.add(
        Marker(
          point: _origemManual!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: AppConfig.brandLight,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            alignment: Alignment.center,
            child: const Text('A',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }
    if (_destino != null && !_destino!.eu) {
      m.add(
        Marker(
          point: LatLng(_destino!.lat, _destino!.lon),
          width: 34,
          height: 34,
          child: const Icon(Icons.location_on,
              size: 34, color: AppConfig.accentLight),
        ),
      );
    }
    for (final v in _veiculosRt) {
      final l = _porId(v.linhaId);
      if (l == null) continue;
      m.add(
        Marker(
          point: LatLng(v.lat, v.lon),
          width: 32,
          height: 32,
          child: Container(
            decoration: BoxDecoration(
              color: l.cor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 5)
              ],
            ),
            child: const Icon(Icons.directions_bus,
                color: Colors.white, size: 17),
          ),
        ),
      );
    }
    return m;
  }

  void _abrirModalParada(PontoParada s) {
    final dk = MotorHorarios.tipoDia(_d);
    final itens = <({LinhaOnibus l, String k, int? t})>[];

    for (final o in s.linhasAtivas) {
      final l = _porId(o.id);
      if (l == null) continue;
      final ps = MotorHorarios.passagens(l, dk, s.lat, s.lon, 45.0);
      final ks = o.s.isNotEmpty
          ? [o.s]
          : ['T', 'B'].where((k) => (l.dep[dk] ?? {}).containsKey(k)).toList();
      for (final k in ks) {
        itens.add((l: l, k: k, t: ps[k]));
      }
    }
    itens.sort((a, b) {
      if (a.t == null && b.t == null) return 0;
      if (a.t == null) return 1;
      if (b.t == null) return -1;
      return a.t!.compareTo(b.t!);
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.tituloExibicao(),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              if (s.nome.isNotEmpty && s.enderecoSemNumero.isNotEmpty)
                Text(
                  s.enderecoSemNumero,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: itens.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final x = itens[i];
                    final rotSent = x.l.ttu
                        ? (x.k == 'T' ? 'sentido bairro' : 'sentido Terminal')
                        : (x.k == 'T' ? 'ida' : 'volta');
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _trechoSel = LatLng(s.lat, s.lon));
                        _selecionarLinha(x.l.id,
                            manterTrecho: true, sentIni: x.k);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            _BadgeLinha(linha: x.l),
                            const SizedBox(width: 10),
                            Expanded(child: Text(rotSent)),
                            Text(
                              x.t != null ? '≈ ${MotorHorarios.hm(x.t!)}' : '—',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.directions_bus),
                  label: const Text('Como chegar de ônibus aqui'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _definirDestino(
                      nome: s.tituloExibicao(),
                      lat: s.lat,
                      lon: s.lon,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Componentes do Painel Inferior ──
  Widget _construirCabecalhoBusca(bool isDark) {
    return Container(
      color: isDark ? AppConfig.brandDark : AppConfig.brandLight,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'FOZTRANS',
                  style: TextStyle(
                    color: AppConfig.brandLight,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Linhas de ônibus',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    for (final l in ['pt', 'es', 'en'])
                      GestureDetector(
                        onTap: () => setState(() => _lang = l),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          color: _lang == l ? Colors.white : Colors.transparent,
                          child: Text(
                            l.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _lang == l
                                  ? AppConfig.brandLight
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Para onde você quer ir?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _aoDigitarBusca,
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF14212B)),
                  decoration: InputDecoration(
                    hintText: 'Linha, ponto ou endereço…',
                    filled: true,
                    fillColor:
                        isDark ? AppConfig.panelDark : AppConfig.panelLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _aoDigitarBusca('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                width: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor:
                        isDark ? AppConfig.panelDark : AppConfig.panelLight,
                    foregroundColor:
                        isDark ? Colors.white : AppConfig.brandLight,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() {
                    _alvoAlfinete = 'para';
                    _escolhendoNoMapa = true;
                  }),
                  child: const Icon(Icons.place),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirListaInicial(bool isDark) {
    final q = MotorHorarios.semAcento(_searchController.text.trim());
    final dk = MotorHorarios.tipoDia(_d);
    final ag = MotorHorarios.agoraMin();

    final ls = _linhasPublicas.where((l) {
      final bateBusca =
          q.isEmpty || MotorHorarios.semAcento('${l.id} ${l.nome}').contains(q);
      final bateAba = q.isNotEmpty ||
          _abaFamilia == 'all' ||
          MotorHorarios.familiaLinha(l) == _abaFamilia;
      return bateBusca && bateAba;
    }).toList();

    final pois = _d.poi.where((p) {
      if (q.isEmpty) return true;
      return MotorHorarios.semAcento('${p.pt} ${p.es} ${p.en}').contains(q);
    }).toList();

    final paradasBusca = q.length >= 3
        ? _d.stops
            .where((s) =>
                s.linhasAtivas.isNotEmpty &&
                MotorHorarios.semAcento('${s.nome} ${s.endereco}').contains(q))
            .take(8)
            .toList()
        : <PontoParada>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.accentLight,
                    foregroundColor: const Color(0xFF1A0F00),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(Icons.my_location, size: 18),
                  ),
                  label: const Text(
                    'Ver linhas e pontos perto de mim',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  onPressed: () =>
                      _obterMinhaLocalizacao(abrirPertoDeMim: true),
                ),
              ),
            ),

          if (q.isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (final tab in [
                    ('all', 'Todas'),
                    ('f0', '10–70'),
                    ('f1', '101–120'),
                    ('f2', '200–250'),
                    ('f3', '310–380'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tab.$2,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        selected: _abaFamilia == tab.$1,
                        onSelected: (_) =>
                            setState(() => _abaFamilia = tab.$1),
                      ),
                    ),
                ],
              ),
            ),

          // Lista de Linhas (usando Material + InkWell + Row, igual ao .lrow do HTML)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: ls.map((l) {
                final dDia = l.dep[dk] ?? {};
                final s0 = ['T', 'B']
                    .where((k) => (dDia[k]?.isNotEmpty ?? false))
                    .firstOrNull;
                final prox = s0 != null
                    ? dDia[s0]!
                        .map((x) => x[0])
                        .where((m) => m >= ag)
                        .firstOrNull
                    : null;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _selecionarLinha(l.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          children: [
                            _BadgeLinha(linha: l),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.nome,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14.5),
                                  ),
                                  if (prox != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'próx. saída ${MotorHorarios.hm(prox)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppConfig.mutedDark
                                              : AppConfig.mutedLight,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: isDark
                                  ? AppConfig.mutedDark
                                  : AppConfig.mutedLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Endereços e locais (Photon + Censo IBGE 2022)
          if (q.length >= 3) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'ENDEREÇOS E LOCAIS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey),
              ),
            ),
            if (_buscandoGeo)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Procurando endereços e locais…',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              )
            else if (_resultadosGeo.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Nada encontrado em Foz do Iguaçu com esse nome.',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: _resultadosGeo.map((r) {
                    return _ItemLocalPin(
                      icone: r.icone,
                      titulo: r.nome,
                      subtitulo: r.sub,
                      isDark: isDark,
                      onTap: () =>
                          _definirDestino(nome: r.nome, lat: r.lat, lon: r.lon),
                    );
                  }).toList(),
                ),
              ),
          ],

          // Pontos de Parada encontrados na busca
          if (paradasBusca.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'PONTOS DE PARADA',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: paradasBusca.map((s) {
                  return _ItemLocalPin(
                    icone: 'P',
                    titulo: s.tituloExibicao(),
                    subtitulo:
                        (s.nome.isNotEmpty && s.endereco.isNotEmpty) ? s.endereco : '',
                    isDark: isDark,
                    onTap: () {
                      _mapController.move(LatLng(s.lat, s.lon), 17.0);
                      _abrirModalParada(s);
                    },
                  );
                }).toList(),
              ),
            ),
          ],

          // Pontos Turísticos e Terminais
          if (pois.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'PONTOS TURÍSTICOS E TERMINAIS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: pois.map((p) {
                  return _ItemLocalPin(
                    icone: p.ic,
                    titulo: p.nomePorIdioma(_lang),
                    isDark: isDark,
                    onTap: () => _definirDestino(
                      nome: p.nomePorIdioma(_lang),
                      lat: p.lat,
                      lon: p.lon,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Detalhe da Linha e Quadro de Horários ──
  Widget _construirBarraLinha(LinhaOnibus l, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppConfig.lineDark : AppConfig.lineLight),
        ),
      ),
      child: Row(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.brandLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => _selecionarLinha(null),
            child: const Text('← Voltar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          _BadgeLinha(linha: l, grande: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.nome,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirDetalheLinha(LinhaOnibus l, bool isDark) {
    final hk = MotorHorarios.tipoDia(_d);
    final ehHoje = _diaSel == hk;
    final ag = MotorHorarios.agoraMin();
    final pares = (l.dep[_diaSel] ?? {})[_sentidoSel] ?? [];

    final listaHorarios = <({int m, int idx, int u, int si})>[];
    for (int i = 0; i < pares.length; i++) {
      final mSaida = pares[i][0];
      final si = pares[i][1];
      if (_trechoSel != null) {
        final r = MotorHorarios.aoLongo(
            l.shapes[si], _trechoSel!.latitude, _trechoSel!.longitude);
        if (r.d > 45.0) continue;
        final c = mSaida +
            MotorHorarios.minCedo(l, l.shapes[si], _diaSel, mSaida, r.f);
        final u = mSaida +
            MotorHorarios.minTarde(l, l.shapes[si], _diaSel, mSaida, r.f);
        listaHorarios.add((m: c, idx: i, u: u, si: si));
      } else {
        listaHorarios.add((m: mSaida, idx: i, u: mSaida, si: si));
      }
    }

    final proximos =
        ehHoje ? listaHorarios.where((x) => x.u >= ag).take(3).toList() : [];
    final nPassados = (ehHoje && proximos.isNotEmpty)
        ? listaHorarios.where((x) => x.u < ag).length
        : 0;
    final visiveis = listaHorarios
        .where((x) => _verPassados || nPassados == 0 || x.u >= ag)
        .toList();

    final mv = MotorHorarios.marcasVar(l, _diaSel, _sentidoSel);

    String rotuloSentido(String s) {
      if (!l.ttu) return s == 'T' ? 'Sentido ida' : 'Sentido volta';
      if (s == 'T') {
        return (l.id == '10' || l.id == '380')
            ? 'Saindo do Centro'
            : 'Saindo do Terminal (TTU)';
      }
      return 'Saindo do bairro';
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_trechoSel != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                border: Border.all(color: AppConfig.accentLight, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trecho selecionado no mapa',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextButton(
                    onPressed: () => setState(() => _trechoSel = null),
                    child: const Text('Mostrar todos os horários'),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              for (final d in [
                ('DU', 'Dias úteis'),
                ('SAB', 'Sábado'),
                ('DOM', 'Domingo'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _diaSel == d.$1
                            ? AppConfig.brandLight
                            : (isDark
                                ? AppConfig.chipDark
                                : AppConfig.chipLight),
                        foregroundColor: _diaSel == d.$1
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: l.dep.containsKey(d.$1)
                          ? () => setState(() {
                                _diaSel = d.$1;
                                _viagemSelIdx = null;
                              })
                          : null,
                      child: Text(d.$2,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              for (final s in ['T', 'B']
                  .where((k) => (l.dep[_diaSel]?[k]?.isNotEmpty ?? false)))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _sentidoSel == s
                            ? AppConfig.brandLight
                            : (isDark
                                ? AppConfig.chipDark
                                : AppConfig.chipLight),
                        foregroundColor: _sentidoSel == s
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => setState(() {
                        _sentidoSel = s;
                        _viagemSelIdx = null;
                      }),
                      child: Text(
                        rotuloSentido(s),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (ehHoje)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: l.cor, width: 8),
                  top: BorderSide(color: l.cor, width: 1.5),
                  right: BorderSide(color: l.cor, width: 1.5),
                  bottom: BorderSide(color: l.cor, width: 1.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _trechoSel != null
                        ? 'PRÓXIMA PASSAGEM NESTE PONTO (ESTIMADO)'
                        : 'PRÓXIMA SAÍDA DO PONTO INICIAL',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  if (proximos.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          MotorHorarios.hm(proximos.first.m),
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          (proximos.first.m - ag) <= 0
                              ? 'agora'
                              : 'em ${proximos.first.m - ag} min',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (proximos.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Depois: ${proximos.skip(1).map((x) => MotorHorarios.hm(x.m)).join(' · ')}',
                          style:
                              const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                  ] else
                    const Text(
                        'Não há mais viagens programadas para hoje.'),
                ],
              ),
            ),

          const SizedBox(height: 14),
          Text(
            'QUADRO DE HORÁRIOS · ${listaHorarios.length} VIAGENS',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          if (nPassados > 0)
            TextButton(
              onPressed: () => setState(() => _verPassados = !_verPassados),
              child: Text(_verPassados
                  ? 'Ocultar horários que já passaram'
                  : 'Mostrar horários que já passaram ($nPassados)'),
            ),
          const SizedBox(height: 6),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: visiveis.map((item) {
              final mk = mv.m[item.si] ?? '';
              final temAst = mv.ast.contains(item.si);
              final selecionado = _viagemSelIdx == item.idx;
              final ehProx =
                  proximos.isNotEmpty && item.idx == proximos.first.idx;

              return InkWell(
                onTap: () => setState(() {
                  _viagemSelIdx = selecionado ? null : item.idx;
                }),
                child: Container(
                  width: mv.sig ? 88 : 68,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: selecionado
                        ? l.bgc
                        : (isDark ? AppConfig.panelDark : AppConfig.panelLight),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selecionado
                          ? l.bgc
                          : ehProx
                              ? AppConfig.accentLight
                              : (isDark
                                  ? AppConfig.lineDark
                                  : AppConfig.lineLight),
                      width: ehProx ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${MotorHorarios.hm(item.m)}${temAst ? '*' : ''}${(!mv.sig && mk.isNotEmpty) ? ' $mk' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: (selecionado || ehProx)
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: 14,
                          color: selecionado ? l.ink : null,
                        ),
                      ),
                      if (mv.sig && mk.isNotEmpty)
                        Text(
                          mk,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: selecionado ? l.ink : Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          if (mv.leg.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...mv.leg.map(
              (g) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    children: [
                      TextSpan(
                        text: '${g[0]} ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: g[1]),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Painel de Destino e Planejador de Viagens (A -> B) ──
  Widget _construirBarraDestino(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppConfig.lineDark : AppConfig.lineLight),
        ),
      ),
      child: Row(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.brandLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => setState(() {
              _destino = null;
              _plano = null;
              _opcaoPlanoSel = null;
            }),
            child: const Text('← Voltar',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _destino!.nome,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirPainelDestino(bool isDark) {
    final dest = _destino!;
    final dk = MotorHorarios.tipoDia(_d);

    final proximasLinhas = _linhasPublicas
        .map((l) => (l: l, d: MotorHorarios.distLinha(l, dest.lat, dest.lon)))
        .toList()
      ..sort((a, b) => a.d.compareTo(b.d));
    final perto500 = proximasLinhas.where((x) => x.d <= 500).toList();
    final listaExibir =
        perto500.isNotEmpty ? perto500 : proximasLinhas.take(3).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!dest.eu) ...[
            const Text(
              'COMO CHEGAR DE ÔNIBUS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppConfig.brandLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('A',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _origemController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'De onde você sai?',
                      filled: true,
                      fillColor:
                          isDark ? AppConfig.panelDark : AppConfig.panelLight,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Usar minha localização',
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _obterMinhaLocalizacao(),
                ),
                IconButton(
                  tooltip: 'Escolher a partida no mapa',
                  icon: const Icon(Icons.place),
                  onPressed: () => setState(() {
                    _alvoAlfinete = 'de';
                    _escolhendoNoMapa = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_plano != null) ...[
              if (_plano!.pertoAPe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'O destino fica a ${_plano!.metrosDireto} m da partida: dá para ir a pé.',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
              if (_plano!.ops.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Não encontrei viagem para hoje a partir de agora, direta ou com uma troca. Veja abaixo as linhas que passam perto do destino.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                )
              else
                ..._plano!.ops.asMap().entries.map((entry) {
                  final i = entry.key;
                  final o = entry.value;
                  final a = o.legs.first;
                  final z = o.legs.last;
                  final comTroca = o.legs.length > 1;
                  final sel = _opcaoPlanoSel == i;

                  return GestureDetector(
                    onTap: () {
                      setState(() => _opcaoPlanoSel = i);
                      _carregarCaminhadasReais(o);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            isDark ? AppConfig.panelDark : AppConfig.panelLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? AppConfig.accentLight
                              : (isDark
                                  ? AppConfig.lineDark
                                  : AppConfig.lineLight),
                          width: sel ? 2 : 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _BadgeLinha(linha: a.l),
                              const SizedBox(width: 8),
                              Text(
                                'Embarque ≈ ${MotorHorarios.hm(a.t0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                              const Spacer(),
                              Text(
                                comTroca ? '1 troca' : 'sem troca',
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.grey),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Text(
                            '• A pé: ${MotorHorarios.arredonda10(o.rO ?? o.dO)} m até o ponto ${_d.stops[a.k0].tituloExibicao()}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (comTroca) ...[
                            const SizedBox(height: 4),
                            Text(
                              o.ttu
                                  ? '• Troca dentro do Terminal (TTU) ≈ ${MotorHorarios.hm(a.t1)} (espera ≈ ${z.t0 - a.t1} min)'
                                  : '• Desça em ${_d.stops[a.k1].tituloExibicao()} ≈ ${MotorHorarios.hm(a.t1)} e pegue a linha ${z.l.id} ≈ ${MotorHorarios.hm(z.t0)}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '• Desça em ${_d.stops[z.k1].tituloExibicao()} ≈ ${MotorHorarios.hm(z.t1)} (${o.dD <= 200 ? "ao lado do destino" : "${MotorHorarios.arredonda10(o.rD ?? o.dD)} m até o destino"})',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Chegada ≈ ${MotorHorarios.hm(o.chega)} · ${o.chega - o.sai} min de viagem',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppConfig.accentLight),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
            const SizedBox(height: 10),
          ],

          Text(
            perto500.isNotEmpty
                ? 'LINHAS QUE PASSAM PERTO (ATÉ 500 M)'
                : 'LINHAS MAIS PRÓXIMAS',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...listaExibir.map((x) {
            final ps =
                MotorHorarios.passagens(x.l, dk, dest.lat, dest.lon, 500.0);
            final resumoPs = ['T', 'B']
                .where((k) => ps.containsKey(k))
                .map((k) => 'passa ≈ ${MotorHorarios.hm(ps[k]!)}')
                .join(' · ');

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selecionarLinha(x.l.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        _BadgeLinha(linha: x.l),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(x.l.nome,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                'a ${MotorHorarios.arredonda10(x.d)} m${resumoPs.isNotEmpty ? ' · $resumoPs' : ' · sem mais viagens hoje'}',
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BadgeLinha extends StatelessWidget {
  final LinhaOnibus linha;
  final bool grande;
  const _BadgeLinha({required this.linha, this.grande = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: grande ? 54 : 46),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: linha.bgc,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: grande ? 10 : 8, vertical: grande ? 5 : 4),
          child: Text(
            linha.id,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: linha.ink,
              fontWeight: FontWeight.w800,
              fontSize: grande ? 18 : 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemLocalPin extends StatelessWidget {
  final String icone;
  final String titulo;
  final String subtitulo;
  final bool isDark;
  final VoidCallback onTap;

  const _ItemLocalPin({
    required this.icone,
    required this.titulo,
    this.subtitulo = '',
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppConfig.brandLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    icone,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontSize: 14)),
                      if (subtitulo.isNotEmpty)
                        Text(
                          subtitulo,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotaoMapa extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final VoidCallback onTap;
  final bool destaque;

  const _BotaoMapa({
    required this.icone,
    required this.rotulo,
    required this.onTap,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: destaque ? AppConfig.brandLight : Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone,
                  size: 16,
                  color: destaque ? Colors.white : const Color(0xFF14212B)),
              const SizedBox(width: 6),
              Text(
                rotulo,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: destaque ? Colors.white : const Color(0xFF14212B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}