import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transporte_models.dart';

class AvisoFoztrans {
  final int id;
  final String titulo;
  final String mensagem;
  final String tipo; // 'info' ou 'alerta'
  final String linhaAfetada;

  AvisoFoztrans({
    required this.id,
    required this.titulo,
    required this.mensagem,
    required this.tipo,
    required this.linhaAfetada,
  });

  factory AvisoFoztrans.fromMap(Map map) {
    return AvisoFoztrans(
      id: (map['id'] as num?)?.toInt() ?? 0,
      titulo: map['titulo']?.toString() ?? '',
      mensagem: map['mensagem']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? 'info',
      linhaAfetada: map['linha_afetada']?.toString() ?? '',
    );
  }
}

class PontoCustomizado {
  final int id;
  final String acao; // 'adicionar' ou 'remover'
  final String nome;
  final String endereco;
  final double lat;
  final double lon;
  final List<String> linhas;

  PontoCustomizado({
    required this.id,
    required this.acao,
    required this.nome,
    required this.endereco,
    required this.lat,
    required this.lon,
    required this.linhas,
  });

  factory PontoCustomizado.fromMap(Map map) {
    final lStr = map['linhas']?.toString() ?? '';
    return PontoCustomizado(
      id: (map['id'] as num?)?.toInt() ?? 0,
      acao: map['acao']?.toString() ?? 'adicionar',
      nome: map['nome']?.toString() ?? '',
      endereco: map['endereco']?.toString() ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (map['lon'] as num?)?.toDouble() ?? 0.0,
      linhas: lStr
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

class SupabaseService {
  // COLE AQUI A URL E A CHAVE ANON DO SEU PROJETO SUPABASE:
  static const String supabaseUrl = 'https://ndzhniwqbqijjcoyjsav.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_FKeyJhl0fbmWjS6si-qBgw_fZusUiZl';

  // Número de WhatsApp da Ouvidoria Foztrans (para envio de vídeos)
  static const String whatsappFoztrans = '(45) 99999-9999';

  static bool get configurado =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.length > 20;

  Map<String, String> get _headers => {
        'apikey': supabaseAnonKey,
        'Authorization': 'Bearer ' + supabaseAnonKey,
        'Content-Type': 'application/json',
      };

  /// Gera ou recupera um ID único para o aparelho (usado no bloqueio anti-spam)
  Future<String> obterDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('fozbus_device_id');
      if (id == null || id.isEmpty) {
        final rnd = math.Random();
        id = 'dev_' +
            DateTime.now().millisecondsSinceEpoch.toString() +
            '_' +
            rnd.nextInt(999999).toString();
        await prefs.setString('fozbus_device_id', id);
      }
      return id;
    } catch (_) {
      return 'dev_anon';
    }
  }

  /// Descobre o IP público do usuário para controle de spam
  Future<String> obterIpPublico() async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.ipify.org?format=json'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map;
        return j['ip']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// Busca os avisos ativos publicados pela equipe Foztrans
  Future<List<AvisoFoztrans>> buscarAvisosAtivos() async {
    if (!configurado) return [];
    try {
      final uri = Uri.parse(
          supabaseUrl + '/rest/v1/avisos?ativo=eq.true&order=criado_em.desc');
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final lista = jsonDecode(resp.body) as List;
        return lista
            .whereType()
            .map((m) => AvisoFoztrans.fromMap(m))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Busca pontos adicionados ou removidos pelo painel gerenciador e aplica no mapa
  Future<void> aplicarPontosCustomizados(DadosTransporteGeral d) async {
    if (!configurado) return;
    try {
      final uri =
          Uri.parse(supabaseUrl + '/rest/v1/pontos_custom?order=criado_em.asc');
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;

      final lista = (jsonDecode(resp.body) as List)
          .whereType()
          .map((m) => PontoCustomizado.fromMap(m))
          .toList();

      for (final pc in lista) {
        if (pc.acao == 'remover') {
          d.stops.removeWhere((s) =>
              (s.lat - pc.lat).abs() < 0.0002 &&
              (s.lon - pc.lon).abs() < 0.0002);
        } else if (pc.acao == 'adicionar') {
          final jaExiste = d.stops.any((s) =>
              (s.lat - pc.lat).abs() < 0.0001 &&
              (s.lon - pc.lon).abs() < 0.0001);
          if (!jaExiste) {
            final novo = PontoParada(
              index: d.stops.length,
              lat: pc.lat,
              lon: pc.lon,
              nome: pc.nome,
              linhasRaw: pc.linhas,
              endereco: pc.endereco,
              sentidosRaw: List<String>.filled(pc.linhas.length, ''),
            );
            novo.linhasAtivas = pc.linhas
                .map((id) => LinhaSentidoParada(id: id, s: ''))
                .toList();
            d.stops.add(novo);
          }
        }
      }
    } catch (_) {}
  }

  /// Faz upload da foto anexada para o Supabase Storage e retorna o link público
  Future<String?> enviarFoto(Uint8List bytes, String extensao) async {
    if (!configurado) return null;
    try {
      final nomeArq = 'foto_' +
          DateTime.now().millisecondsSinceEpoch.toString() +
          '.' +
          extensao;
      final uri = Uri.parse(
          supabaseUrl + '/storage/v1/object/fotos_reclamacoes/' + nomeArq);
      final resp = await http
          .post(
            uri,
            headers: {
              'apikey': supabaseAnonKey,
              'Authorization': 'Bearer ' + supabaseAnonKey,
              'Content-Type': 'image/' + (extensao == 'png' ? 'png' : 'jpeg'),
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return supabaseUrl +
            '/storage/v1/object/public/fotos_reclamacoes/' +
            nomeArq;
      }
    } catch (_) {}
    return null;
  }

  /// Envia a reclamação / ocorrência para o Supabase
  Future<String> enviarReclamacao({
    required String categoria,
    required String linha,
    required String prefixo,
    required String horarioOcorrido,
    required String localOuTela,
    required String descricao,
    Uint8List? fotoBytes,
    String fotoExt = 'jpg',
  }) async {
    if (!configurado) {
      return 'Configure a URL e a chave do Supabase em lib/services/supabase_service.dart';
    }

    try {
      final deviceId = await obterDeviceId();
      final ip = await obterIpPublico();
      String fotoUrl = '';

      if (fotoBytes != null) {
        final urlUp = await enviarFoto(fotoBytes, fotoExt);
        if (urlUp != null) fotoUrl = urlUp;
      }

      final uri = Uri.parse(supabaseUrl + '/rest/v1/reclamacoes');
      final body = jsonEncode({
        'categoria': categoria,
        'linha': linha.trim(),
        'prefixo': prefixo.trim(),
        'horario_ocorrido': horarioOcorrido.trim(),
        'local_ou_tela': localOuTela.trim(),
        'descricao': descricao.trim(),
        'foto_url': fotoUrl,
        'device_id': deviceId,
        'ip_usuario': ip,
      });

      final resp = await http
          .post(uri, headers: _headers, body: body)
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return 'OK';
      }
      if (resp.body.contains('USUARIO_BLOQUEADO')) {
        return 'Seu acesso para envio de mensagens foi bloqueado pela moderação do Foztrans.';
      }
      return 'Não foi possível enviar no momento (Código ' +
          resp.statusCode.toString() +
          ').';
    } catch (_) {
      return 'Erro de conexão ao enviar relato. Verifique sua internet.';
    }
  }
}