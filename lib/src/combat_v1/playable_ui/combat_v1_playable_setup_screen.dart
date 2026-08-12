/// Combat Ver.1 Playable 1B — Setup Screen
/// （docs/design/combat_v1_playable_match_ui.md Playable 1B追記「9章
/// Setup Screen」）。
///
/// Human（Player A）/CPU（Player B）のwrestlerを選び、Match Screenへ
/// 遷移する。production 4 wrestler（misaki/jack/akari/reina）のみを
/// 対象とし、display nameは`combatV1ProductionWrestlerRegistry`を
/// source of truthにする。同一wrestler同士（mirror match）も禁止しない。
library;

import 'package:flutter/material.dart';

import '../combat_v1_production_match_setup.dart';
import 'combat_v1_playable_match_screen.dart';
import 'combat_v1_playable_ui_formatters.dart';

const _pink = Color(0xffff477e);
const _gold = Color(0xffffc857);
const _cardSurface = Color(0xff211527);

/// Setup画面本体。
class CombatV1PlayableSetupScreen extends StatefulWidget {
  const CombatV1PlayableSetupScreen({super.key});

  @override
  State<CombatV1PlayableSetupScreen> createState() =>
      _CombatV1PlayableSetupScreenState();
}

class _CombatV1PlayableSetupScreenState
    extends State<CombatV1PlayableSetupScreen> {
  // 69章「Setup Default」——どちらでもよいが、Human/CPUで異なる
  // production wrestlerをdefaultにしておく。
  String _humanWrestlerId = 'akari';
  String _cpuWrestlerId = 'reina';

  void _start() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CombatV1PlayableMatchScreen(
          humanWrestlerId: _humanWrestlerId,
          cpuWrestlerId: _cpuWrestlerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Combat Ver.1 対戦')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _ExperimentalBadge(),
                const SizedBox(height: 12),
                const Text(
                  'Human（あなた） vs CPUの1試合を最後まで遊べます。'
                  '同じレスラー同士（ミラーマッチ）も選択できます。',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                _WrestlerPicker(
                  key: const Key('combat_v1_playable_setup_human_picker'),
                  title: 'あなたのレスラー（YOU）',
                  selectedId: _humanWrestlerId,
                  onSelected: (id) => setState(() => _humanWrestlerId = id),
                ),
                const SizedBox(height: 16),
                _WrestlerPicker(
                  key: const Key('combat_v1_playable_setup_cpu_picker'),
                  title: 'CPUのレスラー',
                  selectedId: _cpuWrestlerId,
                  onSelected: (id) => setState(() => _cpuWrestlerId = id),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('combat_v1_playable_setup_start_button'),
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text('Start Match'),
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

class _ExperimentalBadge extends StatelessWidget {
  const _ExperimentalBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: _pink),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Experimental ・ Combat Ver.1',
          style: TextStyle(fontSize: 12, color: _pink, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _WrestlerPicker extends StatelessWidget {
  const _WrestlerPicker({
    super.key,
    required this.title,
    required this.selectedId,
    required this.onSelected,
  });

  final String title;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, color: _gold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final wrestlerId in combatV1PlayableWrestlerOrder)
              _WrestlerChoiceCard(
                wrestlerId: wrestlerId,
                selected: wrestlerId == selectedId,
                onTap: () => onSelected(wrestlerId),
              ),
          ],
        ),
      ],
    );
  }
}

class _WrestlerChoiceCard extends StatelessWidget {
  const _WrestlerChoiceCard({
    required this.wrestlerId,
    required this.selected,
    required this.onTap,
  });

  final String wrestlerId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = combatV1PlayableWrestlerDisplayName(wrestlerId);
    // Playable 1C「Wrestler Description」——production data（ENERGY
    // Pool）から安全に取得できる範囲で、名前だけでは分からない違いを
    // 1行で示す。新しいbalance説明を捏造しない（既存の公開静的data
    // そのままの表示に留める）。
    final energyPool = combatV1ProductionWrestlerRegistry[wrestlerId]!.wrestler.energyPool;
    final energyLabel = combatV1PlayableEnergyCostLabel(energyPool.amounts);
    return Semantics(
      // Playable 1C「Accessibility Semantics」——selectedを明示する。
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        key: Key('combat_v1_playable_wrestler_choice_${wrestlerId}_'
            '${selected ? "selected" : "unselected"}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _pink : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected)
                const Icon(Icons.check_circle, color: _pink, size: 18)
              else
                const Icon(Icons.radio_button_unchecked, color: Colors.white38, size: 18),
              const SizedBox(height: 6),
              Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'ENERGY $energyLabel',
                key: Key('combat_v1_playable_wrestler_energy_$wrestlerId'),
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
