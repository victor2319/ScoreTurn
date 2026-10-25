import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/score.dart';
import '../core/score_document.dart';
import '../core/recognition_client.dart';
import 'annotated_page.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key, required this.score});
  final Score score;
  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  final _endpoint = TextEditingController(), _token = TextEditingController();
  final _client = RecognitionClient();
  ScoreDocument? _document;
  bool _busy = false;
  int _page = 0;
  String _message = '上传照片后自动识别小节、音符和翻页点。首次使用需配置识谱服务。';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DocumentStore.load(widget.score);
      if (mounted) setState(() => _document = d);
    } catch (e) {
      if (mounted) setState(() => _message = '本地识谱数据读取失败：$e');
    }
  }

  @override
  void dispose() {
    _client.cancel();
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ScoreDocument> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '正在处理，请稍候。可以返回取消联网请求。';
    });
    try {
      final d = await action();
      if (!mounted) return;
      d.reviewed = false;
      await DocumentStore.save(widget.score, d);
      if (mounted)
        setState(() {
          _document = d;
          _page = 0;
          _message = '识别完成，请检查每页小节框、音符和橙色翻页点，再确认保存。';
        });
    } catch (e) {
      if (mounted) setState(() => _message = '处理失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ScoreDocument> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) throw const FormatException('未选择文件');
    final bytes = await file.readAsBytes();
    if (bytes.length > 32 * 1024 * 1024)
      throw const FormatException('文件超过 32 MB');
    return ScoreDocument.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _edit(int id) async {
    final d = _document!, m = _document!.measures[id];
    final box = TextEditingController(
      text: m.box.map((v) => (v * 100).toStringAsFixed(2)).join(', '),
    );
    final notes = TextEditingController(
      text: m.events.map((e) => e.pitches.join(' ')).join('\n'),
    );
    var trigger = d.turnAfter[m.page] == id;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('第 ${id + 1} 小节（原谱编号 ${m.label}）'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: box,
                  decoration: const InputDecoration(labelText: '边框百分比：左、上、右、下'),
                ),
                TextField(
                  controller: notes,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '音符 MIDI 编号，每行一个起音／和弦',
                    helperText: '中央 C = 60；每行用空格分隔，保留行数。',
                  ),
                ),
                CheckboxListTile(
                  value: trigger,
                  onChanged: (v) => update(() => trigger = v!),
                  title: const Text('设为本页翻页触发小节'),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final oldBox = m.box,
                    oldEvents = m.events.toList(),
                    oldTrigger = d.turnAfter[m.page];
                try {
                  final values = box.text
                      .split(RegExp(r'[,，\s]+'))
                      .where((v) => v.isNotEmpty)
                      .map((v) => double.parse(v) / 100)
                      .toList();
                  final lines = notes.text.trim().isEmpty
                      ? <String>[]
                      : notes.text.trim().split('\n');
                  if (lines.length != m.events.length)
                    throw const FormatException('音符事件行数须保持不变');
                  m.box = values;
                  for (var i = 0; i < lines.length; i++) {
                    final pitches = lines[i]
                        .trim()
                        .split(RegExp(r'\s+'))
                        .map(int.parse)
                        .toList();
                    m.events[i] = ScoreEvent(
                      oldEvents[i].beat,
                      oldEvents[i].duration,
                      pitches,
                    );
                  }
                  d.turnAfter[m.page] = trigger
                      ? id
                      : (oldTrigger == id ? null : oldTrigger);
                  d.validate();
                  d.reviewed = false;
                  Navigator.pop(ctx, true);
                } catch (e) {
                  m.box = oldBox;
                  m.events.setAll(0, oldEvents);
                  d.turnAfter[m.page] = oldTrigger;
                  update(() => error = '$e');
                }
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    box.dispose();
    notes.dispose();
    if (saved == true && mounted)
      setState(() => _message = '修改尚未保存，请点击“确认校对并保存”。');
  }

  Future<void> _order() async {
    final d = _document!,
        controller = TextEditingController(
          text: _document!.order.map((i) => i + 1).join(','),
        );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('实际演奏顺序'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('使用图片标记的连续编号。例：1,2,3,1,2,4。反复的小节重复填写。'),
              TextField(controller: controller, maxLines: 5),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final previous = d.order;
                try {
                  d.order = controller.text
                      .split(RegExp(r'[,，\s]+'))
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.parse(s) - 1)
                      .toList();
                  d.validate();
                  if (d.order.isEmpty) throw const FormatException('顺序不能为空');
                  d.reviewed = false;
                  Navigator.pop(ctx);
                } catch (e) {
                  d.order = previous;
                  update(() => error = '$e');
                }
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final d = _document!;
    try {
      d.reviewed = true;
      if (!d.ready) throw const FormatException('请先检查音符与实际演奏顺序');
      await DocumentStore.save(widget.score, d);
      if (mounted) setState(() => _message = '已保存，可从曲库打开“离线音符跟随”。');
    } catch (e) {
      d.reviewed = false;
      if (mounted) setState(() => _message = '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _document;
    return Scaffold(
      appBar: AppBar(title: const Text('识谱与校对')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_message),
                  if (d == null) ...[
                    TextField(
                      controller: _endpoint,
                      decoration: const InputDecoration(
                        labelText: '识谱服务地址 https://…/recognize',
                      ),
                    ),
                    TextField(
                      controller: _token,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '服务令牌（仅本次使用，不保存）',
                      ),
                    ),
                    const Text('点击联网识谱会将这份曲谱的所有照片上传到上述服务；演奏时不会联网。'),
                  ],
                  Wrap(
                    spacing: 8,
                    children: [
                      if (d == null)
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => _client.recognize(
                                    widget.score,
                                    _endpoint.text,
                                    _token.text,
                                  ),
                                ),
                          child: const Text('联网识谱'),
                        ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _run(_import),
                        child: const Text('导入识谱 JSON'),
                      ),
                      if (d != null)
                        TextButton(
                          onPressed: _busy ? null : _order,
                          child: const Text('校正演奏顺序'),
                        ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
            if (d != null) ...[
              if (d.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(d.warnings.join('\n'), maxLines: 3),
                ),
              Expanded(
                child: AnnotatedPage(
                  path: widget.score.localPaths[_page],
                  document: d,
                  page: _page,
                  onMeasure: _busy ? null : _edit,
                ),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('第 ${_page + 1}/${d.pages.length} 页 · 点击小节框校正'),
                  IconButton(
                    onPressed: _page < d.pages.length - 1
                        ? () => setState(() => _page++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('确认校对并保存'),
                  ),
                ],
              ),
            ] else
              const Expanded(child: Center(child: Text('保留原谱照片，识别结果单独保存在本机。'))),
          ],
        ),
      ),
    );
  }
}
