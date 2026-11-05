import 'dart:async';
import 'package:flutter/material.dart';
import '../models/transporte_models.dart';
import '../services/api_service.dart';
import '../utils/motor_horarios.dart';

class PainelTtuScreen extends StatefulWidget {
  final DadosTransporteGeral dados;
  const PainelTtuScreen({super.key, required this.dados});

  @override
  State<PainelTtuScreen> createState() => _PainelTtuScreenState();
}

class _PainelTtuScreenState extends State<PainelTtuScreen> {
  final ApiService _api = ApiService();
  late List<GrupoLinhaOperacional> _grupos;
  List<VeiculoTempoReal> _veiculos = [];
  int _rtTimestamp = 0;
  String _alaSelecionada = ''; // '' = Todas, '1', '2', '3'
  Timer? _timerRelogio;
  Timer? _timerRt;
  DateTime _agoraDt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _grupos = MotorHorarios.prepara(widget.dados);
    _buscarTempoReal();
    _timerRelogio = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _agoraDt = DateTime.now());
    });
    _timerRt = Timer.periodic(const Duration(seconds: 20), (_) {
      _buscarTempoReal();
    });
  }

  @override
  void dispose() {
    _timerRelogio?.cancel();
    _timerRt?.cancel();
    super.dispose();
  }

  Future<void> _buscarTempoReal() async {
    final ids = <String>{};
    for (final g in _grupos) {
      ids.addAll(g.ids);
    }
    final res = await _api.baixaRT(ids.toList());
    if (mounted && res.t > 0) {
      setState(() {
        _rtTimestamp = res.t;
        _veiculos = res.v;
      });
    }
  }

  Color _corStatus(String c) {
    switch (c) {
      case 'term':
      case 'saindo':
        return const Color(0xFF23D160);
      case 'cheg':
        return const Color(0xFFFFB020);
      case 'prev':
        return const Color(0xFFFF7849);
      default:
        return const Color(0xFFA0AEC0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dk = MotorHorarios.tipoDia(widget.dados, _agoraDt);
    final nomeDia = dk == 'DOM'
        ? 'Domingo'
        : dk == 'SAB'
            ? 'Sábado'
            : 'Dias úteis';

    final filtrados = _grupos.where((g) {
      if (_alaSelecionada.isEmpty) return true;
      return g.ala == _alaSelecionada;
    }).toList();

    final itens = <({GrupoLinhaOperacional g, List<SituacaoCalculada> s})>[];
    for (final g in filtrados) {
      final sit = MotorHorarios.situacaoTtu(g, dk, _veiculos, _rtTimestamp);
      if (sit != null && sit.isNotEmpty) {
        itens.add((g: g, s: sit));
      }
    }

    // Ordena pelas próximas saídas
    itens.sort((a, b) => a.s.first.x.m.compareTo(b.s.first.x.m));

    final hh = _agoraDt.hour.toString().padLeft(2, '0');
    final mm = _agoraDt.minute.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF0B1218),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12325B),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Painel TTU · Próximas Saídas',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              '$nomeDia · ${_rtTimestamp > 0 ? "GPS ao vivo ativo" : "Horários programados"}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$hh:$mm',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF9A3D),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtro de Alas do Terminal
          Container(
            color: const Color(0xFF131F2B),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final op in [
                  ('', 'Todas as Alas'),
                  ('1', 'Ala 1'),
                  ('2', 'Ala 2'),
                  ('3', 'Ala 3'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            op.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: _alaSelecionada == op.$1
                                  ? const Color(0xFF1A0F00)
                                  : Colors.white70,
                            ),
                          ),
                        ),
                        selected: _alaSelecionada == op.$1,
                        selectedColor: const Color(0xFFF07800),
                        backgroundColor: const Color(0xFF1E2D3D),
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => _alaSelecionada = op.$1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: itens.isEmpty
                ? const Center(
                    child: Text(
                      'Sem mais partidas programadas para hoje.',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: itens.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = itens[idx];
                      final g = item.g;
                      final principal = item.s.first;
                      final seguintes = item.s.skip(1).take(3).toList();
                      final corSt = _corStatus(principal.c);

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF131D26),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF243442)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Número da Linha + Ala
                            Column(
                              children: [
                                Container(
                                  constraints: const BoxConstraints(minWidth: 58),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: g.cor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    g.id,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                if (g.ala.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'ALA ${g.ala}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(width: 12),
                            // Destino, Variação e Próximos horários
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.dest,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (principal.x.r.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        MotorHorarios.cap(principal.x.r),
                                        style: const TextStyle(
                                          color: Color(0xFFFFB020),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (principal.sub.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        principal.sub,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (seguintes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Depois: ${seguintes.map((s) => MotorHorarios.hm(s.h ?? s.x.m)).join(' · ')}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Horário principal e badge de situação
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  MotorHorarios.hm(principal.h ?? principal.x.m),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 24,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: corSt.withOpacity(0.18),
                                    border: Border.all(color: corSt),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    principal.t,
                                    style: TextStyle(
                                      color: corSt,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}