import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class NotificacaoService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inicializado = false;
  static Future<void>? _initFuture;
  static const String _prefKeyVistos = 'fozbus_avisos_notificados_v1';

  /// Inicializa o sistema de notificações com trava contra chamadas simultâneas
  static Future<void> inicializar() {
    if (kIsWeb || _inicializado) return Future.value();
    _initFuture ??= _executarInicializacao();
    return _initFuture!;
  }

  static Future<void> _executarInicializacao() async {
    try {
      const androidConfig =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initConfig = InitializationSettings(android: androidConfig);

      await _plugin.initialize(settings: initConfig);
      _inicializado = true;

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    } catch (_) {
      _initFuture = null;
    }
  }

  /// Verifica se há avisos novos e dispara na barra do celular somente após a permissão estar pronta
  static Future<void> verificarEDispararNovosAvisos(
      List<AvisoFoztrans> avisosAtivos) async {
    if (kIsWeb || avisosAtivos.isEmpty) return;
    try {
      await inicializar();

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final permitido = await androidPlugin.areNotificationsEnabled();
        if (permitido == false) return;
      }

      final prefs = await SharedPreferences.getInstance();
      final jaVistos =
          (prefs.getStringList(_prefKeyVistos) ?? <String>[]).toSet();

      bool mudou = false;
      for (final av in avisosAtivos) {
        final idStr = av.id.toString();
        if (!jaVistos.contains(idStr)) {
          jaVistos.add(idStr);
          mudou = true;

          final prefixoLinha = av.linhaAfetada.isNotEmpty
              ? '[Linha ' + av.linhaAfetada + '] '
              : '';
          await mostrarNotificacao(
            id: av.id,
            titulo: prefixoLinha + av.titulo,
            mensagem: av.mensagem,
            urgente: av.tipo == 'alerta',
          );
        }
      }

      if (mudou) {
        await prefs.setStringList(_prefKeyVistos, jaVistos.toList());
      }
    } catch (_) {}
  }

  /// Exibe a notificação na barra de status do Android
  static Future<void> mostrarNotificacao({
    required int id,
    required String titulo,
    required String mensagem,
    bool urgente = false,
  }) async {
    if (kIsWeb) return;
    if (!_inicializado) await inicializar();

    try {
      final androidDetails = AndroidNotificationDetails(
        urgente ? 'fozbus_alertas_urgentes' : 'fozbus_avisos_gerais',
        urgente ? 'Alertas Urgentes FozBus' : 'Avisos FozBus',
        channelDescription:
            'Avisos operacionais e comunicados da equipe FOZTRANS',
        icon: '@mipmap/ic_launcher',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(mensagem),
      );

      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        id: id,
        title: titulo,
        body: mensagem,
        notificationDetails: details,
      );
    } catch (_) {}
  }
}