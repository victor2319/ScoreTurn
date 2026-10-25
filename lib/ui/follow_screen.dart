import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/chroma.dart';
import '../core/microphone.dart';
import '../core/score.dart';
import '../core/score_document.dart';
import '../core/score_follower.dart';
import 'annotated_page.dart';

class FollowScreen extends StatefulWidget {
  const FollowScreen({super.key, required this.score, required this.document});
  final Score score;
  final ScoreDocument document;
  @override
  State<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends State<FollowScreen>
    with WidgetsBindingObserver {
  final _mic = MicrophoneGate();
  late final ScoreFollower _follower;
  bool _listening = false, _busy = false, _manualHold = false;
  int _page = 0, _generation = 0, _lastTurnOccurrence = -1;
  int? _tailPage, _tailMeasure;
  String _status = '点击小节可定位起点。识谱和音频匹配均为实验功能。';
  @override
  void initState() {
    super.initState();
    _follower = ScoreFollower(widget.document);
    _page = widget.document.measures[_follower.measureId].page;
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_mic.dispose());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _stop() async {
    _generation++;
    if (mounted)
      setState(() {
        _listening = false;
        _busy = true;
        _status = '已暂停；恢复时会重新确认当前位置';
      });
    await _mic.stop();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _start() async {
    if (_busy || _listening) return;
    final generation = ++_generation;
    _follower.seek(_follower.occurrence);
    setState(() {
      _busy = true;
      _listening = true;
      _status = '正在监听并确认当前小节';
    });
    final extractor = ChromaExtractor((feature) {
      if (!mounted || !_listening || generation != _generation) return;
      _follower.add(feature.chroma, rms: feature.rms, onset: feature.onset);
      final measure = widget.document.measures[_follower.measureId];
      final target = _follower.turnTarget;
      setState(() {
        _status = _follower.locked
            ? '已匹配第 ${measure.id + 1} 小节 · ${(100 * _follower.confidence).round()}% 相似度'
            : '定位不确定，保持页面；可点击小节手动校准';
        if (!_manualHold && _follower.locked) {
          if (_tailPage != null && measure.page != _tailPage) {
            _tailPage = null;
            _tailMeasure = null;
          }
          // Follow repeat jumps only after confirming the note on the new page.
          if (_tailPage == null) _page = measure.page;
          if (target != null && _lastTurnOccurrence != _follower.occurrence) {
            _tailPage = measure.page;
            _tailMeasure = measure.id;
            _page = target;
            _lastTurnOccurrence = _follower.occurrence;
          }
        }
      });
    });
    try {
      await _mic.arm(
        onStart: () {},
        onMeter: (_, __) {},
        onPcm: extractor.add,
        onError: (e) {
          if (mounted && generation == _generation) {
            _generation++;
            setState(() {
              _listening = false;
              _busy = false;
              _status = '收音中断：$e';
            });
          }
        },
      );
    } catch (e) {
      if (mounted && generation == _generation)
        setState(() {
          _listening = false;
          _status = '无法收音：$e';
        });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _seek(int id) {
    // Prefer the upcoming occurrence, so a repeated passage is unambiguous.
    var occurrence = -1;
    for (var i = _follower.occurrence; i < widget.document.order.length; i++) {
      if (widget.document.order[i] == id) {
        occurrence = i;
        break;
      }
    }
    occurrence = occurrence < 0
        ? widget.document.order.indexOf(id)
        : occurrence;
    if (occurrence < 0) {
      setState(() => _status = '该小节不在已确认的演奏顺序中');
      return;
    }
    try {
      _follower.seek(occurrence);
      setState(() {
        _page = widget.document.measures[_follower.measureId].page;
        _manualHold = false;
        _tailPage = null;
        _tailMeasure = null;
        _lastTurnOccurrence = -1;
        _status = '已定位第 ${id + 1} 小节，等待音符确认';
      });
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  void _manualPage(int page) {
    setState(() {
      _page = page;
      _manualHold = true;
      _tailPage = null;
      _status = '手动翻页已接管；点击当前演奏的小节恢复跟随';
    });
  }

  Widget _tail() {
    final d = widget.document, page = _tailPage!;
    final remaining = d.measures
        .where((m) => m.page == page && m.id >= _tailMeasure!)
        .toList();
    final top =
        (remaining.map((m) => m.box[1]).reduce((a, b) => a < b ? a : b) - 0.025)
            .clamp(0.0, 1.0);
    final bottom =
        (remaining.map((m) => m.box[3]).reduce((a, b) => a > b ? a : b) + 0.025)
            .clamp(0.0, 1.0);
    final aspect =
        d.pages[page].width / (d.pages[page].height * (bottom - top));
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, size) => ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: -top * size.maxHeight / (bottom - top),
                  height: size.maxHeight / (bottom - top),
                  child: Image.file(
                    File(widget.score.localPaths[page]),
                    fit: BoxFit.fill,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('离线跟随 · 第 ${_page + 1} 页'),
      actions: [
        IconButton(
          tooltip: '回到开头',
          onPressed: () {
            _follower.seek(0);
            _seek(widget.document.order.first);
          },
          icon: const Icon(Icons.restart_alt),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_tailPage != null) ...[
            const Text('上一页剩余小节'),
            Expanded(flex: 2, child: _tail()),
            const Divider(height: 4),
          ],
          Expanded(
            flex: 5,
            child: AnnotatedPage(
              path: widget.score.localPaths[_page],
              document: widget.document,
              page: _page,
              active: _follower.locked ? _follower.measureId : null,
              onMeasure: _seek,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, maxLines: 3),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                onPressed: _page > 0 ? () => _manualPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : (_listening ? _stop : _start),
                icon: Icon(_listening ? Icons.pause : Icons.mic),
                label: Text(_listening ? '暂停跟随' : '开始跟随'),
              ),
              IconButton(
                onPressed: _page < widget.score.pageCount - 1
                    ? () => _manualPage(_page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '全程本地分析，不保存录音。复杂和声、踏板和重复音可能需要手动校准。',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}
