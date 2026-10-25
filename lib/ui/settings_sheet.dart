import 'package:flutter/material.dart';
import '../core/score.dart';

/// Editable mapping is intentionally explicit: PDF/photos are not OMR-transcribed.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.score});
  final Score score;
  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _title;
  late final TextEditingController _bpm;
  late final TextEditingController _beats;
  late final TextEditingController _advance;
  late final TextEditingController _first;
  late final List<TextEditingController> _last;
  String? _validation;

  @override
  void initState() {
    super.initState();
    final s = widget.score;
    _title = TextEditingController(text: s.title);
    _bpm = TextEditingController(text: s.bpm.toStringAsFixed(0));
    _beats = TextEditingController(text: '${s.beatsPerMeasure}');
    _advance = TextEditingController(text: '${s.advanceMeasures}');
    _first = TextEditingController(text: '${s.firstMeasure}');
    _last = s.lastMeasureByPage.map((i) => TextEditingController(text: '$i')).toList();
  }

  @override
  void dispose() {
    for (final c in [_title, _bpm, _beats, _advance, _first, ..._last]) c.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final updated = widget.score.update(
        title: _title.text.trim(), bpm: double.parse(_bpm.text),
        beatsPerMeasure: int.parse(_beats.text),
        advanceMeasures: int.parse(_advance.text),
        firstMeasure: int.parse(_first.text),
        lastMeasureByPage: _last.map((c) => int.parse(c.text)).toList(),
      );
      updated.validate();
      Navigator.of(context).pop(updated);
    } catch (e) {
      setState(() => _validation = '检查输入：页末小节须递增；BPM 30–300；每小节 1–12 拍；提前 1–8 小节。 ($e)');
    }
  }

  Widget _field(String title, TextEditingController ctl, {bool numeric = true}) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
        controller: ctl, keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: title, isDense: true,
          border: const OutlineInputBorder()),
      ));

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(padding: EdgeInsets.only(
      left: 22, right: 22, top: 20, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('乐谱设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('照片与 PDF 尚不自动识谱，请输入每页最后一个小节编号。',
          style: TextStyle(color: Color(0xFF627182))),
        const SizedBox(height: 18),
        _field('乐谱名称', _title, numeric: false),
        Row(children: [Expanded(child: _field('预设速度 BPM', _bpm)), const SizedBox(width: 10),
          Expanded(child: _field('每小节拍数', _beats))]),
        Row(children: [Expanded(child: _field('首小节编号', _first)), const SizedBox(width: 10),
          Expanded(child: _field('提前翻页小节数', _advance))]),
        const Text('页面与小节映射', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (var i = 0; i < _last.length; i++)
          _field('第 ${i + 1} 页的最后小节编号', _last[i]),
        if (_validation != null) Text(_validation!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('保存并返回'))),
      ])),
    ));
  }
}
