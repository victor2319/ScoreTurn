import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/clock.dart';
import '../core/microphone.dart';
import '../core/score.dart';
import '../core/score_library.dart';
import '../core/turn_policy.dart';
import '../core/session_log.dart';
import 'settings_sheet.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.score, required this.library});
  final Score score;
  final ScoreLibrary library;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  late Score _score;
  late BeatClock _clock;
  late TurnPolicy _policy;
  late SessionLog _log;
  final MicrophoneGate _mic = MicrophoneGate();
  PdfControllerPinch? _pdf;
  Timer? _ticker;
  int _page = 0;
  bool _armed = false;
  bool _calibrated = false;
  bool _manualHold = false;
  bool _autoTurn = true;
  bool _showNextPreview = false;
  double _rms = 0;
  String _status = '等待开始';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _score = widget.score;
    _clock = _newClock();
    _policy = TurnPolicy(_score)..reset(currentMeasure: _score.firstMeasure, currentPage: 0);
    _log = SessionLog(scoreId: _score.id, startedAt: DateTime.now());
    _log.add('reader_open', measure: _clock.measure, page: _page, bpm: _clock.bpm);
    _setupPdf();
    unawaited(WakelockPlus.enable());
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  BeatClock _newClock() => BeatClock(bpm: _score.bpm,
      beatsPerMeasure: _score.beatsPerMeasure, firstMeasure: _score.firstMeasure);

  void _setupPdf() {
    if (_score.isPdf) {
      _pdf = PdfControllerPinch(
        document: PdfDocument.openFile(_score.localPaths.first),
        initialPage: 1,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Never advance the musical clock while the operating system suspends us.
      if (_clock.running) _clock.pause();
      _policy.reposition(measure: _clock.measure, page: _page);
      _showNextPreview = false;
      _log.add('app_interrupted', measure: _clock.measure, page: _page);
      unawaited(_mic.stop());
      if (mounted) {
        setState(() {
          _armed = false;
          _status = '应用中断，已暂停。请手动恢复';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _log.add('reader_close', measure: _clock.measure, page: _page);
    unawaited(_saveLogSafely());
    _clock.pause();
    unawaited(_mic.dispose());
    _pdf?.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _tick() {
    if (!mounted || !_clock.running) return;
    final decision = _policy.update(
      measure: _clock.measure, page: _page, running: _clock.running,
      automaticEnabled: _autoTurn && !_manualHold,
    );
    _showNextPreview = decision.previewNext;
    if (decision.turnPage) {
      _changePage(_page + 1, manual: false);
      _status = '预设节拍自动翻页（尚未接入和声确认）';
    }
    setState(() {});
  }

  Future<void> _saveLogSafely() async {
    try {
      await _log.saveTo(Directory('${widget.library.root.path}/diagnostics'));
    } catch (_) {
      // User-visible copy diagnostics remains available even if disk is full.
    }
  }

  Future<void> _copyDiagnostics() async {
    _log.add('diagnostics_copy', measure: _clock.measure, page: _page);
    await Clipboard.setData(ClipboardData(text: _log.toJsonLines()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制本次会话 ${_log.count} 条事件（不含录音内容）')),
    );
  }

  void _changeTempo(double delta) {
    final next = (_clock.bpm + delta).clamp(30.0, 300.0);
    if ((next - _clock.bpm).abs() < 0.001) return;
    _clock.setTempo(next);
    _log.add('tempo_adjust', measure: _clock.measure, page: _page, bpm: next);
    setState(() => _status = '演奏速度调整为 ${next.toStringAsFixed(0)} BPM');
  }

  void _changePage(int requested, {bool manual = true}) {
    final page = requested.clamp(0, _score.pageCount - 1).toInt();
    if (page == _page) return;
    setState(() {
      _page = page;
      _showNextPreview = false;
      _policy.reposition(measure: _clock.measure, page: _page);
      _log.add(manual ? 'manual_page' : 'automatic_page',
          measure: _clock.measure, page: _page, bpm: _clock.bpm);
      if (manual && _clock.running) {
        _manualHold = true;
        _status = '已手动接管。需要时点“恢复自动”';
      }
    });
    if (_score.isPdf) {
      // The widget has a frame by the time a user can tap page controls.
      try { _pdf?.jumpToPage(_page + 1); } catch (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pdf?.jumpToPage(_page + 1);
        });
      }
    }
  }

  Future<void> _armMic() async {
    if (_armed || _clock.running) return;
    // Always start listening at the first displayed score page/measure.
    _clock.reset();
    _policy.reset(currentMeasure: _clock.measure, currentPage: 0);
    _log.add('microphone_arm', measure: _clock.measure, page: 0);
    if (_score.isPdf) {
      try { _pdf?.jumpToPage(1); } catch (_) {}
    }
    setState(() {
      _page = 0;
      _manualHold = false;
      _armed = true;
      _calibrated = false;
      _status = '正在校准环境音，请稍后开始弹奏';
    });
    try {
      await _mic.arm(
        onStart: () {
          if (!mounted || !_armed) return;
          _clock.start();
          _policy.reset(currentMeasure: _clock.measure, currentPage: _page);
          _log.add('microphone_start', measure: _clock.measure, page: _page, bpm: _clock.bpm,
            detail: 'chunks=${_mic.receivedChunks};bytes=${_mic.receivedBytes}');
          setState(() { _armed = false; _status = '检测到明显起音，节拍计时开始'; });
        },
        onMeter: (value, calibrated) {
          if (!mounted) return;
          setState(() {
            _rms = value;
            _calibrated = calibrated;
            if (_armed && calibrated) _status = '正在等待第一声钢琴（仅音量检测）';
          });
        },
        onError: (error) {
          if (!mounted) return;
          _clock.pause();
          _log.add('microphone_error', measure: _clock.measure, page: _page, detail: '$error');
          setState(() { _armed = false; _status = '麦克风异常：$error'; });
        },
      );
    } catch (e) {
      _log.add('microphone_start_failure', detail: '$e');
      if (mounted) setState(() { _armed = false; _status = '无法启动麦克风：$e'; });
    }
  }

  Future<void> _manualStart() async {
    await _mic.stop();
    if (!mounted) return;
    _clock.reset();
    _clock.start();
    _policy.reset(currentMeasure: _clock.measure, currentPage: 0);
    _log.add('manual_start', measure: _clock.measure, page: 0, bpm: _clock.bpm);
    setState(() {
      _armed = false;
      _manualHold = false;
      _page = 0;
      _status = '手动开始计时';
    });
    if (_score.isPdf) {
      try { _pdf?.jumpToPage(1); } catch (_) {}
    }
  }

  Future<void> _pauseOrResume() async {
    if (_armed) {
      await _mic.stop();
      _log.add('cancel_listening', measure: _clock.measure, page: _page);
      if (mounted) setState(() { _armed = false; _status = '已取消监听'; });
    } else if (_clock.running) {
      _clock.pause();
      _policy.reposition(measure: _clock.measure, page: _page);
      _log.add('manual_pause', measure: _clock.measure, page: _page);
      setState(() => _status = '已暂停');
    } else if (_clock.beats > 0) {
      _clock.resume();
      _policy.reposition(measure: _clock.measure, page: _page);
      _log.add('manual_resume', measure: _clock.measure, page: _page);
      setState(() => _status = '继续按节拍计时');
    }
  }

  Future<void> _reset() async {
    await _mic.stop();
    _clock.reset();
    _policy.reset(currentMeasure: _clock.measure, currentPage: 0);
    _log.add('reset', measure: _clock.measure, page: 0);
    if (!mounted) return;
    setState(() {
      _page = 0; _manualHold = false; _armed = false; _rms = 0;
      _status = '已重置';
    });
    if (_score.isPdf) { try { _pdf?.jumpToPage(1); } catch (_) {} }
  }

  Future<void> _settings() async {
    if (_clock.running) _clock.pause();
    await _mic.stop();
    if (!mounted) return;
    setState(() => _armed = false);
    final updated = await showModalBottomSheet<Score>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => SettingsSheet(score: _score),
    );
    if (updated == null) return;
    try {
      await widget.library.replace(updated);
      if (!mounted) return;
      setState(() {
        _score = updated;
        _clock = _newClock();
        _policy = TurnPolicy(_score)..reset(currentMeasure: _score.firstMeasure, currentPage: 0);
        _log.add('settings_changed', measure: _clock.measure, page: 0, bpm: _clock.bpm);
        _page = 0;
        _manualHold = false;
        _status = '配置已保存，等待重新开始';
      });
      if (_score.isPdf) { try { _pdf?.jumpToPage(1); } catch (_) {} }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Widget _nextPagePreview() {
    final upcoming = _page + 1;
    if (_score.isPdf) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.auto_stories, size: 20),
        const SizedBox(width: 8),
        Text('下一页：${upcoming + 1} / ${_score.pageCount}（PDF 预览待实现）'),
      ]);
    }
    return Row(children: [
      const Icon(Icons.auto_stories, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text('下一页预览 · 第 ${upcoming + 1} 页')),
      ClipRRect(borderRadius: BorderRadius.circular(5),
        child: Image.file(File(_score.localPaths[upcoming]), width: 72,
          height: 68, fit: BoxFit.cover, alignment: Alignment.topCenter)),
    ]);
  }

  Widget _scorePage() {
    if (_score.isPdf) {
      return IgnorePointer(ignoring: _clock.running,
        child: PdfViewPinch(
          controller: _pdf!, scrollDirection: Axis.horizontal,
          onPageChanged: (page) {
            if (page != _page + 1 && mounted) {
              setState(() {
                _page = page - 1;
                _policy.reposition(measure: _clock.measure, page: _page);
                _log.add('pdf_swipe', measure: _clock.measure, page: _page);
                if (_clock.running) {
                  _manualHold = true;
                  _status = '已滑动乐谱，自动翻页暂停';
                }
              });
            }
          },
          onDocumentError: (error) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF 加载失败：$error')));
          },
        ),
      );
    }
    return InteractiveViewer(key: ValueKey('${_score.id}-$_page'),
      minScale: 0.8, maxScale: 5,
      child: Center(child: Image.file(File(_score.localPaths[_page]), fit: BoxFit.contain,
        errorBuilder: (_, error, stack) => Center(child: Text('图像加载失败：$error')))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final measure = _clock.measure;
    final landscape = MediaQuery.of(context).size.width > 750;
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_score.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: landscape ? 18 : 15, fontWeight: FontWeight.w600)),
          Text('第 ${_page + 1} / ${_score.pageCount} 页 · 第 $measure 小节（估算）',
            style: const TextStyle(fontSize: 12, color: Color(0xFFD4E7E7))),
        ]),
        actions: [
          IconButton(tooltip: '复制本次诊断日志', onPressed: _copyDiagnostics,
            icon: const Icon(Icons.fact_check_outlined)),
          IconButton(tooltip: '乐谱节拍与翻页设置', onPressed: _settings,
            icon: const Icon(Icons.tune)),
        ],
      ),
      body: Column(children: [
        Expanded(child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: const Color(0xFFFDFBF4), child: _scorePage())),
          if (_showNextPreview && _clock.running && _page < _score.pageCount - 1)
            Positioned(top: 10, right: 12, child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xDE123E47),
                  borderRadius: BorderRadius.circular(8)),
              child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text('即将翻页 · 当前谱面保持显示',
                  style: TextStyle(color: Colors.white, fontSize: 12))),
            ))),
        ])),
        if (_showNextPreview && _clock.running && _page < _score.pageCount - 1)
          ColoredBox(color: const Color(0xFFE3F1EF), child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: _nextPagePreview(),
          )),
        ColoredBox(color: Colors.white, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(_clock.running ? Icons.graphic_eq : (_armed ? Icons.mic : Icons.pause_circle_outline),
                size: 18, color: _clock.running ? const Color(0xFF007E80) : Colors.blueGrey),
              const SizedBox(width: 7),
              Expanded(child: Text(_status, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12))),
              Text('${_clock.bpm.toStringAsFixed(0)} BPM', style: labelStyle),
              const SizedBox(width: 8),
              Text('第 $measure 小节', style: labelStyle),
            ]),
            const SizedBox(height: 6),
            if (_armed) LinearProgressIndicator(value: _calibrated ?
              (_rms * 10).clamp(0.0, 1.0) : null, minHeight: 3),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5, runSpacing: 4, children: [
              IconButton.filledTonal(onPressed: _page > 0 ? () => _changePage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left), tooltip: '上一页'),
              IconButton.filledTonal(onPressed: _page < _score.pageCount - 1
                  ? () => _changePage(_page + 1) : null,
                icon: const Icon(Icons.chevron_right), tooltip: '下一页'),
              IconButton(onPressed: () { _clock.seekMeasure(math.max(_score.firstMeasure, measure - 1));
                _policy.reposition(measure: _clock.measure, page: _page);
                _log.add('seek_measure', measure: _clock.measure, page: _page);
                setState(() => _status = '手动校准：第 ${_clock.measure} 小节'); },
                icon: const Icon(Icons.remove_circle_outline), tooltip: '当前小节 -1'),
              IconButton(onPressed: () { _clock.seekMeasure(math.min(_score.lastMeasure, measure + 1));
                _policy.reposition(measure: _clock.measure, page: _page);
                _log.add('seek_measure', measure: _clock.measure, page: _page);
                setState(() => _status = '手动校准：第 ${_clock.measure} 小节'); },
                icon: const Icon(Icons.add_circle_outline), tooltip: '当前小节 +1'),
              if (_manualHold) TextButton(onPressed: () => setState(() {
                _manualHold = false;
                _policy.reposition(measure: _clock.measure, page: _page);
                _log.add('auto_resume', measure: _clock.measure, page: _page);
                _status = '恢复按节拍自动翻页';
              }), child: const Text('恢复自动')),
              IconButton(onPressed: () => _changeTempo(-5),
                icon: const Icon(Icons.speed_outlined), tooltip: 'BPM -5'),
              Text(_clock.bpm.toStringAsFixed(0), style: labelStyle),
              IconButton(onPressed: () => _changeTempo(5),
                icon: const Icon(Icons.add_box_outlined), tooltip: 'BPM +5'),
              IconButton(onPressed: _reset, icon: const Icon(Icons.restart_alt), tooltip: '重置'),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              if (!_clock.running && !_armed && _clock.beats == 0)
                Expanded(child: FilledButton.icon(onPressed: _armMic,
                  icon: const Icon(Icons.mic), label: const Text('监听开始'))),
              if (!_clock.running && !_armed && _clock.beats == 0) const SizedBox(width: 8),
              if (!_clock.running && !_armed && _clock.beats == 0)
                Expanded(child: OutlinedButton.icon(onPressed: _manualStart,
                  icon: const Icon(Icons.play_arrow), label: const Text('手动开始'))),
              if (_clock.running || _armed || _clock.beats > 0)
                Expanded(child: FilledButton.icon(onPressed: _pauseOrResume,
                  icon: Icon(_clock.running || _armed ? Icons.pause : Icons.play_arrow),
                  label: Text(_armed ? '停止监听' : (_clock.running ? '暂停' : '继续')))),
              const SizedBox(width: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('自动翻页', style: TextStyle(fontSize: 12)),
                Switch(value: _autoTurn, onChanged: (v) => setState(() {
                  _autoTurn = v;
                  _policy.reposition(measure: _clock.measure, page: _page);
                  _log.add('toggle_automatic', measure: _clock.measure, page: _page,
                    detail: '$v');
                })),
              ]),
            ]),
            const SizedBox(height: 3),
            Text('实验模式：计时依赖预设 BPM，不包含 POC-24 的和声确认；演出请保持手动翻页。',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
              textAlign: TextAlign.center),
          ]),
        )),
      ]),
    );
  }
}
