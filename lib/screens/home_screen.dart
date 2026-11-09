import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../config/app_settings.dart';
import '../models/transporte_models.dart';
import '../services/api_service.dart';
import '../services/notificacao_service.dart';
import '../services/supabase_service.dart';
import '../utils/motor_horarios.dart';
import 'configuracoes_screen.dart';
import 'painel_ttu_screen.dart';
import 'reclamacao_screen.dart';

class HomeScreen extends StatefulWidget {
  final DadosTransporteGeral dadosIniciais;
  const HomeScreen({super.key, required this.dadosIniciais});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final SupabaseService _supa = SupabaseService();
  final MapController _mapController = MapController();
  final ScrollController _listScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _origemController = TextEditingController();

  static const Color _corVermelhoDestaque = Color(0xFFE53935);
  static const Color _corGpsAzul = Color(0xFF0B57D0);

  late DadosTransporteGeral _d;
  String _abaFamilia = 'all'; // 'all', 'f0', 'f1', 'f2', 'f3'
  double _zoomAtual = 12.2;

  // Altura do painel inferior controlada APENAS pela barra superior
  double _sheetFraction = 0.50;

  // Avisos do Supabase e controle de recolhimento
  List<AvisoFoztrans> _avisosSupa = [];
  bool _avisosMinimizado = false;
  final Set<int> _avisosFechadosLocal = {};

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

  // Ônibus e Avisos em tempo real (atualizados a cada 15s)
  List<VeiculoTempoReal> _veiculosRt = [];
  Timer? _timerRt;

  static const Map<String, Map<String, String>> _i18n = {
    'pt': {
      'title': 'Linhas de ônibus',
      'qlabel': 'Para onde você quer ir?',
      'search': 'Linha, ponto ou endereço…',
      'nearBtn': 'Ver linhas e pontos perto de mim',
      'tall': 'Todas',
      'loc': 'Onde estou',
      'painel_ttu': 'Painel TTU',
      'nextdep': 'próx. saída',
      'placesR': 'ENDEREÇOS E LOCAIS',
      'geoLoad': 'Procurando endereços e locais…',
      'geoNone': 'Nada encontrado em Foz do Iguaçu com esse nome.',
      'stopsG': 'PONTOS DE PARADA',
      'places': 'PONTOS TURÍSTICOS E TERMINAIS',
      'back': '← Voltar',
      'du': 'Dias úteis',
      'sab': 'Sábado',
      'dom': 'Domingo',
      'fromT': 'Saindo do Terminal (TTU)',
      'fromB': 'Saindo do bairro',
      'fromC': 'Saindo do Centro',
      'fromA': 'Sentido ida',
      'fromV': 'Sentido volta',
      'toB': 'sentido bairro',
      'toT': 'sentido Terminal',
      'toA': 'ida',
      'toV': 'volta',
      'nextHere': 'PRÓXIMA PASSAGEM NESTE PONTO (ESTIMADO)',
      'next': 'PRÓXIMA SAÍDA DO PONTO INICIAL',
      'now': 'agora',
      'inmin': 'em {n} min',
      'then': 'Depois',
      'nomore': 'Não há mais viagens programadas para hoje.',
      'timetable': 'QUADRO DE HORÁRIOS',
      'trips': 'VIAGENS',
      'showPast': 'Mostrar horários que já passaram ({n})',
      'hidePast': 'Ocultar horários que já passaram',
      'stretch': 'Trecho selecionado no mapa',
      'allTimes': 'Mostrar todos os horários',
      'tripOf': 'Meia-viagem das {h}',
      'route': 'Trajeto',
      'allRoutes': 'Ver meia-viagem atual',
      'how': 'COMO CHEGAR DE ÔNIBUS',
      'deL': 'De onde você sai?',
      'nearL': 'LINHAS QUE PASSAM PERTO (ATÉ 500 M)',
      'noNear': 'LINHAS MAIS PRÓXIMAS',
      'board': 'Embarque',
      'troca1': '1 troca',
      'direto': 'sem troca',
      'pass': 'passa',
      'noPass': 'sem mais viagens hoje',
      'goHere': 'Como chegar de ônibus aqui',
      'pickDest': 'Mova o mapa até o alfinete ficar no seu destino.',
      'pickOrig': 'Mova o mapa até o alfinete ficar no local de partida.',
      'okDest': 'Ir para cá',
      'okOrig': 'Sair daqui',
      'cancel': 'Cancelar',
      'nearYou': 'Perto de você',
      'myLoc': 'Sua localização',
      'locDenied': 'Permissão de localização negada.',
    },
    'es': {
      'title': 'Líneas de autobús',
      'qlabel': '¿Adónde quiere ir?',
      'search': 'Línea, parada o dirección…',
      'nearBtn': 'Ver líneas y paradas cerca de mí',
      'tall': 'Todas',
      'loc': 'Dónde estoy',
      'painel_ttu': 'Panel TTU',
      'nextdep': 'próx. salida',
      'placesR': 'DIRECCIONES Y LUGARES',
      'geoLoad': 'Buscando direcciones y lugares…',
      'geoNone': 'No se encontró nada en Foz do Iguaçu con ese nombre.',
      'stopsG': 'PARADAS DE AUTOBÚS',
      'places': 'ATRACTIVOS Y TERMINALES',
      'back': '← Volver',
      'du': 'Días hábiles',
      'sab': 'Sábado',
      'dom': 'Domingo',
      'fromT': 'Desde la Terminal (TTU)',
      'fromB': 'Desde el barrio',
      'fromC': 'Desde el Centro',
      'fromA': 'Sentido ida',
      'fromV': 'Sentido vuelta',
      'toB': 'hacia el barrio',
      'toT': 'hacia la Terminal',
      'toA': 'ida',
      'toV': 'vuelta',
      'nextHere': 'PRÓXIMO PASO POR ESTE PUNTO (ESTIMADO)',
      'next': 'PRÓXIMA SALIDA DEL PUNTO INICIAL',
      'now': 'ahora',
      'inmin': 'en {n} min',
      'then': 'Después',
      'nomore': 'No hay más viajes programados para hoy.',
      'timetable': 'CUADRO DE HORARIOS',
      'trips': 'VIAJES',
      'showPast': 'Mostrar horarios que ya pasaron ({n})',
      'hidePast': 'Ocultar horarios que ya pasaron',
      'stretch': 'Tramo seleccionado en el mapa',
      'allTimes': 'Mostrar todos los horarios',
      'tripOf': 'Medio viaje de las {h}',
      'route': 'Recorrido',
      'allRoutes': 'Ver medio viaje actual',
      'how': 'CÓMO LLEGAR EN AUTOBÚS',
      'deL': '¿De dónde sale?',
      'nearL': 'LÍNEAS QUE PASAN CERCA (HASTA 500 M)',
      'noNear': 'LÍNEAS MÁS CERCANAS',
      'board': 'Suba',
      'troca1': '1 transbordo',
      'direto': 'sin transbordo',
      'pass': 'pasa',
      'noPass': 'sin más viajes hoy',
      'goHere': 'Cómo llegar en autobús aquí',
      'pickDest': 'Mueva el mapa hasta que el marcador quede en su destino.',
      'pickOrig': 'Mueva el mapa hasta que el marcador quede en la salida.',
      'okDest': 'Ir aquí',
      'okOrig': 'Salir de aquí',
      'cancel': 'Cancelar',
      'nearYou': 'Cerca de usted',
      'myLoc': 'Su ubicación',
      'locDenied': 'Permiso de ubicación denegado.',
    },
    'en': {
      'title': 'Bus lines',
      'qlabel': 'Where do you want to go?',
      'search': 'Line, stop or address…',
      'nearBtn': 'See lines and stops near me',
      'tall': 'All',
      'loc': 'Where am I',
      'painel_ttu': 'TTU Board',
      'nextdep': 'next dep.',
      'placesR': 'ADDRESSES AND PLACES',
      'geoLoad': 'Searching addresses and places…',
      'geoNone': 'Nothing found in Foz do Iguaçu with that name.',
      'stopsG': 'BUS STOPS',
      'places': 'ATTRACTIONS AND TERMINALS',
      'back': '← Back',
      'du': 'Weekdays',
      'sab': 'Saturday',
      'dom': 'Sunday',
      'fromT': 'From the Terminal (TTU)',
      'fromB': 'From the neighbourhood',
      'fromC': 'From the City Centre',
      'fromA': 'Outbound',
      'fromV': 'Inbound',
      'toB': 'outbound',
      'toT': 'to Terminal',
      'toA': 'outbound',
      'toV': 'inbound',
      'nextHere': 'NEXT BUS AT THIS POINT (ESTIMATED)',
      'next': 'NEXT DEPARTURE FROM START',
      'now': 'now',
      'inmin': 'in {n} min',
      'then': 'Then',
      'nomore': 'There are no more scheduled trips today.',
      'timetable': 'TIMETABLE',
      'trips': 'TRIPS',
      'showPast': 'Show earlier times ({n})',
      'hidePast': 'Hide earlier times',
      'stretch': 'Stretch selected on the map',
      'allTimes': 'Show all times',
      'tripOf': '{h} half-trip',
      'route': 'Route',
      'allRoutes': 'View current half-trip',
      'how': 'GETTING THERE BY BUS',
      'deL': 'Where are you leaving from?',
      'nearL': 'LINES PASSING NEARBY (WITHIN 500 M)',
      'noNear': 'NEAREST LINES',
      'board': 'Board',
      'troca1': '1 transfer',
      'direto': 'no transfer',
      'pass': 'passes',
      'noPass': 'no more trips today',
      'goHere': 'Get here by bus',
      'pickDest': 'Move the map until the pin is on your destination.',
      'pickOrig': 'Move the map until the pin is where you leave from.',
      'okDest': 'Go here',
      'okOrig': 'Start here',
      'cancel': 'Cancel',
      'nearYou': 'Near you',
      'myLoc': 'Your location',
      'locDenied': 'Location permission denied.',
    },
  };

  String _t(String k) =>
      _i18n[appSettings.lang]?[k] ?? _i18n['pt']![k] ?? k;

  @override
  void initState() {
    super.initState();
    _d = widget.dadosIniciais;
    MotorHorarios.inicializarDadosMapa(_d,
        modoDaltonismo: appSettings.modoDaltonismo);
    _diaSel = MotorHorarios.tipoDia(_d);

    // Pede permissão de notificação ao entrar no app
    NotificacaoService.inicializar();

    _atualizarDadosEmSegundoPlano();

    // A cada 15 segundos: atualiza posição dos ônibus E busca novos avisos/notificações no Supabase!
    _timerRt = Timer.periodic(const Duration(seconds: 15), (_) {
      _atualizarPosicoesRt();
      _sincronizarAvisosEPontosSupabase();
    });
  }

  @override
  void dispose() {
    _debounceGeo?.cancel();
    _timerRt?.cancel();
    _listScrollController.dispose();
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
    // 1. Busca os ônibus imediatamente ao abrir a tela!
    _atualizarPosicoesRt();
    _sincronizarAvisosEPontosSupabase();

    // 2. Depois confere em segundo plano se há atualização de horários no Drive
    final novo = await _api.baixaDados();
    if (novo != null && mounted) {
      setState(() {
        _d = novo;
        MotorHorarios.inicializarDadosMapa(_d,
            modoDaltonismo: appSettings.modoDaltonismo);
      });
      await _supa.aplicarPontosCustomizados(_d);
    }
  }

  /// Sincroniza avisos e pontos do Supabase a cada 15s e dispara notificação no celular se houver aviso novo
  Future<void> _sincronizarAvisosEPontosSupabase() async {
    await _supa.aplicarPontosCustomizados(_d);
    final avisos = await _supa.buscarAvisosAtivos();
    await NotificacaoService.verificarEDispararNovosAvisos(avisos);
    if (mounted) {
      setState(() {
        _avisosSupa = avisos;
      });
    }
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
    } else {
      for (final l in _linhasPublicas) {
        if (_abaFamilia == 'all' ||
            MotorHorarios.familiaLinha(l) == _abaFamilia) {
          ids.add(l.id);
        }
      }
    }
    if (ids.isEmpty) return;
    final res = await _api.baixaRT(ids.toList());
    if (mounted) {
      setState(() => _veiculosRt = res.v);
    }
  }

  // Arraste exclusivo pela barra superior do painel
  void _arrastarPainel(DragUpdateDetails details) {
    final hTela = MediaQuery.of(context).size.height;
    if (hTela <= 0) return;
    final delta = (details.primaryDelta ?? 0) / hTela;
    setState(() {
      _sheetFraction = (_sheetFraction - delta).clamp(0.14, 0.90);
    });
  }

  void _alternarAlturaPainel() {
    setState(() {
      if (_sheetFraction < 0.28) {
        _sheetFraction = 0.50;
      } else if (_sheetFraction < 0.75) {
        _sheetFraction = 0.88;
      } else {
        _sheetFraction = 0.50;
      }
    });
  }

  ({int? siAtivo, int? siProximo}) _obterShapesMeiaViagem(LinhaOnibus l) {
    final d = l.dep[_diaSel] ?? {};
    final pares = d[_sentidoSel] ?? [];
    if (pares.isEmpty) return (siAtivo: null, siProximo: null);

    int siAtivo;
    if (_viagemSelIdx != null && _viagemSelIdx! < pares.length) {
      siAtivo = pares[_viagemSelIdx!][1];
    } else {
      final ag = MotorHorarios.agoraMin();
      final proxPar = pares.where((p) => p[0] >= ag).firstOrNull;
      if (proxPar != null) {
        siAtivo = proxPar[1];
      } else {
        final cont = <int, int>{};
        for (final p in pares) {
          cont[p[1]] = (cont[p[1]] ?? 0) + 1;
        }
        siAtivo = cont.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
      }
    }

    final outroSentido = _sentidoSel == 'T' ? 'B' : 'T';
    final paresOutro = d[outroSentido] ?? [];
    int? siProximo;
    if (paresOutro.isNotEmpty) {
      final ag = MotorHorarios.agoraMin();
      final proxOutro = paresOutro.where((p) => p[0] >= ag).firstOrNull;
      siProximo = proxOutro != null ? proxOutro[1] : paresOutro.first[1];
    }

    return (siAtivo: siAtivo, siProximo: siProximo);
  }

  void _aoClicarNoOnibus(VeiculoTempoReal v) {
    final l = _porId(v.linhaId);
    if (l == null) return;
    final dk = MotorHorarios.tipoDia(_d);
    final d = l.dep[dk] ?? {};
    String? s = v.sentido == '0'
        ? 'T'
        : v.sentido == '1'
            ? 'B'
            : null;
    int idxViagem = -1;

    int acharIndice(String k, int m) {
      final lista = d[k] ?? [];
      int j = lista.indexWhere((par) => par[0] == m);
      if (j < 0 && m < 180) {
        j = lista.indexWhere((par) => par[0] == m + 1440);
      }
      return j;
    }

    if (v.minSaida != null) {
      if (s != null) {
        idxViagem = acharIndice(s, v.minSaida!);
      }
      if (idxViagem < 0) {
        final outro = (s == 'T') ? 'B' : 'T';
        final j = acharIndice(outro, v.minSaida!);
        if (j >= 0) {
          s = outro;
          idxViagem = j;
        }
      }
    }

    final sDisp =
        ['T', 'B'].where((k) => (d[k]?.isNotEmpty ?? false)).toList();
    final sentidoFinal = (s != null && sDisp.contains(s))
        ? s
        : (sDisp.isNotEmpty ? sDisp.first : 'T');

    setState(() {
      _destino = null;
      _plano = null;
      _trechoSel = null;
      _linhaSelId = l.id;
      _diaSel = dk;
      _sentidoSel = sentidoFinal;
      _viagemSelIdx = idxViagem >= 0 ? idxViagem : null;
      if (idxViagem >= 0) {
        _verPassados = true;
      }
    });

    final pares = d[sentidoFinal] ?? [];
    final si = (idxViagem >= 0 && idxViagem < pares.length)
        ? pares[idxViagem][1]
        : _obterShapesMeiaViagem(l).siAtivo;
    if (si != null && l.shapes[si].p.length >= 2) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(
              [...l.shapes[si].p, LatLng(v.lat, v.lon)]),
          padding: const EdgeInsets.all(48),
          maxZoom: 16.0,
        ),
      );
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
            SnackBar(content: Text(_t('locDenied'))),
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
          _origemNome = _t('myLoc');
          _origemController.text = _origemNome;
          _recalcularPlano();
        } else if (abrirPertoDeMim) {
          _definirDestino(
              nome: _t('nearYou'),
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

        final meias = _obterShapesMeiaViagem(l);
        final pts = <LatLng>[];
        if (meias.siAtivo != null) {
          pts.addAll(l.shapes[meias.siAtivo!].p);
        }
        if (pts.length >= 2 && _trechoSel == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(pts),
                padding: const EdgeInsets.all(44),
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
      final meias = _obterShapesMeiaViagem(lSel);
      if (meias.siAtivo != null) {
        final r = MotorHorarios.aoLongo(
            lSel.shapes[meias.siAtivo!], ll.latitude, ll.longitude);
        if (r.d <= 80) {
          setState(() {
            _trechoSel = LatLng(r.lat, r.lon);
            _viagemSelIdx = null;
          });
        }
      }
      return;
    }

    double menorD = 1e9;
    LatLng? ptMaisPerto;
    LinhaOnibus? linhaMaisPerto;
    for (final l in _linhasPublicas) {
      if (_abaFamilia != 'all' &&
          MotorHorarios.familiaLinha(l) != _abaFamilia) {
        continue;
      }
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

  void _abrirConfiguracoes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConfiguracoesScreen(
          onChanged: () {
            if (!mounted) return;
            setState(() {
              MotorHorarios.inicializarDadosMapa(_d,
                  modoDaltonismo: appSettings.modoDaltonismo);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lSel = _porId(_linhaSelId);
    final uiScale = appSettings.uiScale;
    final hTela = MediaQuery.of(context).size.height;
    final alturaPainel = (hTela * _sheetFraction).clamp(110.0, hTela * 0.90);
    final bottomBotaoLoc =
        (alturaPainel + 12.0).clamp(95.0, hTela - 120.0);

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
                urlTemplate: appSettings.satelite
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

          // Alfinete central em formato de gota vermelha ao escolher Partida/Destino
          if (_escolhendoNoMapa)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 38),
                  child: Icon(
                    Icons.location_on,
                    size: 48,
                    color: _corVermelhoDestaque,
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
                              ? _t('pickDest')
                              : _t('pickOrig'),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _corVermelhoDestaque,
                          foregroundColor: Colors.white,
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
                          _alvoAlfinete == 'para'
                              ? _t('okDest')
                              : _t('okOrig'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _escolhendoNoMapa = false),
                        child: Text(_t('cancel'),
                            style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Botão "Reclamação" no topo direito
          if (!_escolhendoNoMapa)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 12,
              child: Material(
                color: _corVermelhoDestaque,
                borderRadius: BorderRadius.circular(10),
                elevation: 4,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReclamacaoScreen(linhas: _linhasPublicas),
                      ),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 12 * uiScale, vertical: 9 * uiScale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.campaign_rounded,
                            size: 18 * uiScale, color: Colors.white),
                        const SizedBox(width: 6),
                        const Text(
                          'Reclamação',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Botões "Onde estou" + "Painel TTU" juntos acima da aba inferior (subindo e descendo com ela)
          if (!_escolhendoNoMapa)
            Positioned(
              bottom: bottomBotaoLoc,
              right: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Material(
                    color: isDark ? AppConfig.panelDark : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 5,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          _obterMinhaLocalizacao(abrirPertoDeMim: true),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.my_location,
                          color: _minhaLoc != null
                              ? _corGpsAzul
                              : (isDark
                                  ? Colors.white
                                  : const Color(0xFF14212B)),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: AppConfig.brandLight,
                    borderRadius: BorderRadius.circular(12),
                    elevation: 5,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PainelTtuScreen(dados: _d),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tv,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              _t('painel_ttu'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 2. PAINEL INFERIOR INDEPENDENTE:
          // Só sobe/desce ao puxar pela barra superior. Rolar a lista lá dentro NÃO puxa o painel!
          if (!_escolhendoNoMapa)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: alturaPainel,
              child: Material(
                color: isDark ? AppConfig.bgDark : AppConfig.bgLight,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                elevation: 14,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Barra de puxar (único lugar que redimensiona a altura da aba!)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: _arrastarPainel,
                      onTap: _alternarAlturaPainel,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: (lSel == null && _destino == null)
                            ? (isDark
                                ? AppConfig.brandDark
                                : AppConfig.brandLight)
                            : (isDark
                                ? AppConfig.panelDark
                                : AppConfig.bgLight),
                        child: Center(
                          child: Container(
                            width: 52,
                            height: 6,
                            decoration: BoxDecoration(
                              color: (lSel == null && _destino == null)
                                  ? Colors.white70
                                  : Colors.grey.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),

                    if (lSel == null && _destino == null)
                      _construirCabecalhoBusca(isDark)
                    else if (lSel != null)
                      _construirBarraLinha(lSel, isDark)
                    else
                      _construirBarraDestino(isDark),

                    // Lista interna 100% livre para rolar em qualquer altura do painel!
                    Expanded(
                      child: ListView(
                        controller: _listScrollController,
                        padding: EdgeInsets.zero,
                        children: [
                          if (lSel != null)
                            _construirDetalheLinha(lSel, isDark, uiScale)
                          else if (_destino != null)
                            _construirPainelDestino(isDark)
                          else
                            _construirListaInicial(isDark, uiScale),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Seção de Avisos Retrátil / Minimizável ──
  Widget _construirSecaoAvisos(bool isDark) {
    final visiveis = _avisosSupa
        .where((a) => !_avisosFechadosLocal.contains(a.id))
        .toList();
    if (visiveis.isEmpty) return const SizedBox.shrink();

    final temAlerta = visiveis.any((a) => a.tipo == 'alerta');
    final corBarra =
        temAlerta ? const Color(0xFFB91C1C) : AppConfig.brandLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Column(
        children: [
          // Barra compacta para Minimizar / Expandir todos os avisos
          Material(
            color: corBarra,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  setState(() => _avisosMinimizado = !_avisosMinimizado),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      temAlerta
                          ? Icons.warning_amber_rounded
                          : Icons.campaign_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Avisos FOZTRANS (' +
                            visiveis.length.toString() +
                            ')',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      _avisosMinimizado ? 'Mostrar ▼' : 'Minimizar ▲',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_avisosMinimizado) ...[
            const SizedBox(height: 6),
            ...visiveis.map((av) {
              final ehAlerta = av.tipo == 'alerta';
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                decoration: BoxDecoration(
                  color: ehAlerta
                      ? const Color(0xFFB91C1C)
                      : AppConfig.accentLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: ehAlerta
                          ? const Color(0xFF7F1D1D)
                          : AppConfig.accentLight,
                      width: 5,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (av.linhaAfetada.isNotEmpty
                                    ? '[Linha ' + av.linhaAfetada + '] '
                                    : '') +
                                av.titulo,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: ehAlerta ? Colors.white : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            av.mensagem,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: ehAlerta ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: ehAlerta ? Colors.white70 : Colors.grey,
                      ),
                      tooltip: 'Ocultar este aviso',
                      onPressed: () => setState(() {
                        _avisosFechadosLocal.add(av.id);
                      }),
                    ),
                  ],
                ),
              );
            }),
          ],
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
      final meias = _obterShapesMeiaViagem(lSel);

      if (meias.siProximo != null && meias.siProximo != meias.siAtivo) {
        final ptsProx = lSel.shapes[meias.siProximo!].p;
        if (ptsProx.length >= 2) {
          polylines.add(Polyline(
            points: ptsProx,
            color: Colors.white.withOpacity(0.8),
            strokeWidth: 6.0,
          ));
          polylines.add(Polyline(
            points: ptsProx,
            color: lSel.cor.withOpacity(0.75),
            strokeWidth: 3.5,
            pattern: StrokePattern.dashed(segments: const [10, 8]),
          ));
        }
      }

      if (meias.siAtivo != null) {
        final ptsAtivo = lSel.shapes[meias.siAtivo!].p;
        if (ptsAtivo.length >= 2) {
          polylines.add(Polyline(
            points: ptsAtivo,
            color: Colors.white,
            strokeWidth: 10.5,
            pattern: const StrokePattern.solid(),
          ));
          polylines.add(Polyline(
            points: ptsAtivo,
            color: lSel.cor,
            strokeWidth: 6.5,
            pattern: const StrokePattern.solid(),
          ));
        }
      }
      return polylines;
    }

    for (final l in _linhasPublicas) {
      if (_abaFamilia != 'all' &&
          MotorHorarios.familiaLinha(l) != _abaFamilia) {
        continue;
      }
      for (final s in l.shapes.where((x) => x.main == 1)) {
        if (s.p.length < 2) continue;
        polylines.add(Polyline(
          points: s.p,
          color: Colors.white.withOpacity(0.85),
          strokeWidth: 5.5,
        ));
        polylines.add(Polyline(
          points: s.p,
          color: l.cor.withOpacity(0.92),
          strokeWidth: 3.4,
        ));
      }
    }
    return polylines;
  }

  List<Marker> _construirMarkersParadas(LinhaOnibus? lSel) {
    final markers = <Marker>[];
    final icScale = appSettings.mapIconScale;
    final tam = 22.0 * icScale;

    Iterable<PontoParada> stopsFiltrados;
    if (lSel != null) {
      final meias = _obterShapesMeiaViagem(lSel);
      final shAtivo =
          meias.siAtivo != null ? lSel.shapes[meias.siAtivo!] : null;

      stopsFiltrados = _d.stops.where((s) {
        final atendeLinha = s.linhasAtivas.any(
            (o) => o.id == lSel.id && (o.s.isEmpty || o.s == _sentidoSel));
        if (!atendeLinha) return false;
        if (shAtivo == null) return true;
        final distTtu = MotorHorarios.dist(
            s.lat, s.lon, AppConfig.ttuCoords[0], AppConfig.ttuCoords[1]);
        final lim = distTtu <= 200.0 ? 150.0 : 55.0;
        return MotorHorarios.aoLongo(shAtivo, s.lat, s.lon).d <= lim;
      });
    } else {
      stopsFiltrados = _d.stops.where((s) {
        if (s.linhasAtivas.isEmpty) return false;
        if (_abaFamilia == 'all') return true;
        return s.linhasAtivas.any((o) {
          final l = _porId(o.id);
          return l != null && MotorHorarios.familiaLinha(l) == _abaFamilia;
        });
      });
    }

    for (final s in stopsFiltrados) {
      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: tam,
          height: tam,
          child: GestureDetector(
            onTap: () => _abrirModalParada(s),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5 * icScale),
                border: Border.all(
                  color: lSel != null ? lSel.cor : AppConfig.brandLight,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.directions_bus,
                size: 13 * icScale,
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
    final icScale = appSettings.mapIconScale;
    final tam = 30.0 * icScale;
    return _d.poi.map((p) {
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: tam,
        height: tam,
        child: GestureDetector(
          onTap: () => _definirDestino(
            nome: p.nomePorIdioma(appSettings.lang),
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
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13 * icScale,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _construirMarkersEspeciais(LinhaOnibus? lSel) {
    final m = <Marker>[];
    final icScale = appSettings.mapIconScale;
    final mostrarNum = appSettings.mostrarNumeroNoOnibus;

    if (_minhaLoc != null) {
      m.add(
        Marker(
          point: _minhaLoc!,
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: _corGpsAzul.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(5),
            child: Container(
              decoration: BoxDecoration(
                color: _corGpsAzul,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4)
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_trechoSel != null) {
      m.add(
        Marker(
          point: _trechoSel!,
          width: 38,
          height: 38,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_on,
            size: 38,
            color: _corVermelhoDestaque,
          ),
        ),
      );
    }

    if (_origemManual != null) {
      m.add(
        Marker(
          point: _origemManual!,
          width: 26,
          height: 26,
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
          width: 44,
          height: 44,
          alignment: Alignment.topCenter,
          child: const Icon(
            Icons.location_on,
            size: 44,
            color: _corVermelhoDestaque,
          ),
        ),
      );
    }

    if (lSel != null) {
      final meias = _obterShapesMeiaViagem(lSel);
      if (meias.siAtivo != null) {
        final pts = lSel.shapes[meias.siAtivo!].p;
        if (pts.length >= 2) {
          m.add(
            Marker(
              point: pts.first,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: lSel.cor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          );
          m.add(
            Marker(
              point: pts.last,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: lSel.cor, width: 4),
                ),
              ),
            ),
          );
        }
      }
    }

    for (final v in _veiculosRt) {
      if (v.idadeSegundos > 300) continue;
      final l = _porId(v.linhaId);
      if (l == null) continue;
      if (lSel != null && l.id != lSel.id) continue;
      if (lSel == null &&
          _abaFamilia != 'all' &&
          MotorHorarios.familiaLinha(l) != _abaFamilia) {
        continue;
      }

      final wBus = (mostrarNum ? 46.0 : 36.0) * icScale;
      final hBus = 36.0 * icScale;

      m.add(
        Marker(
          key: ValueKey('bus_' +
              v.prefixo +
              '_' +
              v.lat.toString() +
              '_' +
              v.lon.toString()),
          point: LatLng(v.lat, v.lon),
          width: wBus,
          height: hBus,
          child: GestureDetector(
            onTap: () => _aoClicarNoOnibus(v),
            child: Container(
              decoration: BoxDecoration(
                color: mostrarNum ? l.bgc : l.cor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 5)
                ],
              ),
              alignment: Alignment.center,
              child: mostrarNum
                  ? Text(
                      l.id,
                      style: TextStyle(
                        color: l.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.0 * icScale,
                      ),
                    )
                  : Icon(
                      Icons.directions_bus,
                      color: Colors.white,
                      size: 19.0 * icScale,
                    ),
            ),
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
                        ? (x.k == 'T' ? _t('toB') : _t('toT'))
                        : (x.k == 'T' ? _t('toA') : _t('toV'));
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
                              x.t != null
                                  ? '≈ ' + MotorHorarios.hm(x.t!)
                                  : '—',
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
                  label: Text(_t('goHere')),
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
                height: 38,
                constraints: const BoxConstraints(maxWidth: 104),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Image.asset(
                      'assets/fozbus_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text(
                          'FOZBUS',
                          style: TextStyle(
                            color: AppConfig.brandLight,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t('title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              Material(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _abrirConfiguracoes,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t('qlabel'),
            style: const TextStyle(
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
                    hintText: _t('search'),
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
                height: 46,
                width: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: _corVermelhoDestaque,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Colors.white, width: 1.5),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _alvoAlfinete = 'para';
                    _escolhendoNoMapa = true;
                  }),
                  child: const Icon(Icons.location_on, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _construirListaInicial(bool isDark, double uiScale) {
    final q = MotorHorarios.semAcento(_searchController.text.trim());
    final dk = MotorHorarios.tipoDia(_d);
    final ag = MotorHorarios.agoraMin();

    final ls = _linhasPublicas.where((l) {
      final bateBusca = q.isEmpty ||
          MotorHorarios.semAcento(l.id + ' ' + l.nome).contains(q);
      final bateAba = q.isNotEmpty ||
          _abaFamilia == 'all' ||
          MotorHorarios.familiaLinha(l) == _abaFamilia;
      return bateBusca && bateAba;
    }).toList();

    final pois = _d.poi.where((p) {
      if (q.isEmpty) return true;
      return MotorHorarios.semAcento(p.pt + ' ' + p.es + ' ' + p.en)
          .contains(q);
    }).toList();

    final paradasBusca = q.length >= 3
        ? _d.stops
            .where((s) =>
                s.linhasAtivas.isNotEmpty &&
                MotorHorarios.semAcento(s.nome + ' ' + s.endereco).contains(q))
            .take(8)
            .toList()
        : <PontoParada>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seção de Avisos Retrátil / Minimizável
          _construirSecaoAvisos(isDark),

          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.accentLight,
                    foregroundColor: const Color(0xFF1A0F00),
                    padding: EdgeInsets.symmetric(vertical: 12 * uiScale),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(Icons.my_location, size: 18),
                  ),
                  label: Text(
                    _t('nearBtn'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
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
                    ('all', _t('tall')),
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
                        onSelected: (_) {
                          setState(() => _abaFamilia = tab.$1);
                          _atualizarPosicoesRt();
                        },
                      ),
                    ),
                ],
              ),
            ),

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
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10 * uiScale),
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
                                        _t('nextdep') +
                                            ' ' +
                                            MotorHorarios.hm(prox),
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

          if (q.length >= 3) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                _t('placesR'),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey),
              ),
            ),
            if (_buscandoGeo)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(_t('geoLoad'),
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
              )
            else if (_resultadosGeo.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(_t('geoNone'),
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
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

          if (paradasBusca.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                _t('stopsG'),
                style: const TextStyle(
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
                    subtitulo: (s.nome.isNotEmpty && s.endereco.isNotEmpty)
                        ? s.endereco
                        : '',
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

          if (pois.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                _t('places'),
                style: const TextStyle(
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
                    titulo: p.nomePorIdioma(appSettings.lang),
                    isDark: isDark,
                    onTap: () => _definirDestino(
                      nome: p.nomePorIdioma(appSettings.lang),
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
            child: Text(_t('back'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _abrirConfiguracoes,
          ),
        ],
      ),
    );
  }

  Widget _construirDetalheLinha(LinhaOnibus l, bool isDark, double uiScale) {
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
      if (!l.ttu) return s == 'T' ? _t('fromA') : _t('fromV');
      if (s == 'T') {
        return (l.id == '10' || l.id == '380') ? _t('fromC') : _t('fromT');
      }
      return _t('fromB');
    }

    String? tituloViagemSel;
    String? rotaViagemSel;
    if (_viagemSelIdx != null && _viagemSelIdx! < pares.length) {
      final mViagem = pares[_viagemSelIdx!][0];
      final siViagem = pares[_viagemSelIdx!][1];
      tituloViagemSel =
          _t('tripOf').replaceAll('{h}', MotorHorarios.hm(mViagem));
      final nLimpo = MotorHorarios.nomeVarLimpo(l, siViagem);
      rotaViagemSel = nLimpo.isNotEmpty ? nLimpo : l.nome;
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tituloViagemSel != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                border: Border.all(color: l.cor, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tituloViagemSel,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        if (rotaViagemSel != null)
                          Text(
                            _t('route') + ': ' + rotaViagemSel,
                            style: const TextStyle(
                                fontSize: 12.5, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _viagemSelIdx = null),
                    child: Text(_t('allRoutes')),
                  ),
                ],
              ),
            ),

          if (_trechoSel != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppConfig.panelDark : AppConfig.panelLight,
                border: Border.all(color: _corVermelhoDestaque, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(_t('stretch'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _trechoSel = null),
                    child: Text(_t('allTimes')),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              for (final d in [
                ('DU', _t('du')),
                ('SAB', _t('sab')),
                ('DOM', _t('dom')),
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
                        padding:
                            EdgeInsets.symmetric(vertical: 10 * uiScale),
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
                        padding:
                            EdgeInsets.symmetric(vertical: 10 * uiScale),
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
                    _trechoSel != null ? _t('nextHere') : _t('next'),
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
                              ? _t('now')
                              : _t('inmin').replaceAll(
                                  '{n}', (proximos.first.m - ag).toString()),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (proximos.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _t('then') +
                              ': ' +
                              proximos
                                  .skip(1)
                                  .map((x) => MotorHorarios.hm(x.m))
                                  .join(' · '),
                          style:
                              const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                  ] else
                    Text(_t('nomore')),
                ],
              ),
            ),

          const SizedBox(height: 14),
          Text(
            _t('timetable') +
                ' · ' +
                listaHorarios.length.toString() +
                ' ' +
                _t('trips'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          if (nPassados > 0)
            TextButton(
              onPressed: () => setState(() => _verPassados = !_verPassados),
              child: Text(_verPassados
                  ? _t('hidePast')
                  : _t('showPast').replaceAll('{n}', nPassados.toString())),
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
                onTap: () {
                  final novoIdx = selecionado ? null : item.idx;
                  setState(() => _viagemSelIdx = novoIdx);
                  if (novoIdx != null && novoIdx < pares.length) {
                    final pts = l.shapes[pares[novoIdx][1]].p;
                    if (pts.length >= 2) {
                      _mapController.fitCamera(
                        CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(pts),
                          padding: const EdgeInsets.all(48),
                          maxZoom: 16.0,
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: (mv.sig ? 88 : 68) * uiScale,
                  padding: EdgeInsets.symmetric(
                      vertical: 8 * uiScale, horizontal: 4),
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
                        MotorHorarios.hm(item.m) +
                            (temAst ? '*' : '') +
                            ((!mv.sig && mk.isNotEmpty) ? ' ' + mk : ''),
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
                        text: g[0] + ' ',
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
            child: Text(_t('back'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _abrirConfiguracoes,
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
            Text(
              _t('how'),
              style: const TextStyle(
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
                      hintText: _t('deL'),
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
                  icon: const Icon(Icons.my_location),
                  onPressed: () => _obterMinhaLocalizacao(),
                ),
                IconButton(
                  icon: const Icon(Icons.location_on,
                      color: _corVermelhoDestaque),
                  onPressed: () => setState(() {
                    _alvoAlfinete = 'de';
                    _escolhendoNoMapa = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_plano != null) ...[
              if (_plano!.ops.isNotEmpty)
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
                                _t('board') + ' ≈ ' + MotorHorarios.hm(a.t0),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 18),
                              ),
                              const Spacer(),
                              Text(
                                comTroca ? _t('troca1') : _t('direto'),
                                style: const TextStyle(
                                    fontSize: 12.5, color: Colors.grey),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Text(
                            '• A pé: ' +
                                MotorHorarios.arredonda10(o.rO ?? o.dO)
                                    .toString() +
                                ' m → ' +
                                _d.stops[a.k0].tituloExibicao(),
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (comTroca) ...[
                            const SizedBox(height: 4),
                            Text(
                              o.ttu
                                  ? '• Terminal (TTU) ≈ ' +
                                      MotorHorarios.hm(a.t1) +
                                      ' → Linha ' +
                                      z.l.id +
                                      ' ≈ ' +
                                      MotorHorarios.hm(z.t0)
                                  : '• ' +
                                      _d.stops[a.k1].tituloExibicao() +
                                      ' ≈ ' +
                                      MotorHorarios.hm(a.t1) +
                                      ' → Linha ' +
                                      z.l.id +
                                      ' ≈ ' +
                                      MotorHorarios.hm(z.t0),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '• ' +
                                _d.stops[z.k1].tituloExibicao() +
                                ' ≈ ' +
                                MotorHorarios.hm(z.t1),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '≈ ' +
                                MotorHorarios.hm(o.chega) +
                                ' · ' +
                                (o.chega - o.sai).toString() +
                                ' min',
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
            perto500.isNotEmpty ? _t('nearL') : _t('noNear'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...listaExibir.map((x) {
            final ps =
                MotorHorarios.passagens(x.l, dk, dest.lat, dest.lon, 500.0);
            final resumoPs = ['T', 'B']
                .where((k) => ps.containsKey(k))
                .map((k) => _t('pass') + ' ≈ ' + MotorHorarios.hm(ps[k]!))
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
                                MotorHorarios.arredonda10(x.d).toString() +
                                    ' m · ' +
                                    (resumoPs.isNotEmpty
                                        ? resumoPs
                                        : _t('noPass')),
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