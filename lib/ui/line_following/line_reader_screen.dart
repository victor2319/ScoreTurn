import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/score.dart';
import '../../core/microphone.dart';
import '../../core/line_following/line_gate.dart';
import '../../core/line_following/line_model.dart';
import '../../core/line_following/line_pages.dart';
import '../../core/line_following/line_spectrum.dart';
import 'line_page_view.dart';

class LineReaderScreen extends StatefulWidget {
  const LineReaderScreen({super.key, required this.score});
  final Score score;
  @override
  State<LineReaderScreen> createState() => _LineReaderScreenState();
}

class _LineReaderScreenState extends State<LineReaderScreen>
    with WidgetsBindingObserver {
  final _mic = MicrophoneGate(), _model = LineModel();
  final _queue = Queue<LineAudioFrame>();
  late final LinePages _pages;
  late final Future<void> _setupFuture;
  PreparedLinePage? _page, _tail;
  LineGate? _gate;
  Future<void>? _worker, _starting;
  bool _ready = false,
      _busy = true,
      _listening = false,
      _closing = false,
      _swapping = false,
      _automatic = true;
  int _epoch = 0, _frameCount = 0;
  double _latency = 0, _rms = 0;
  String _status = '正在加载离线模型，并准备前两页…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages = LinePages(widget.score);
    _setupFuture = _setup();
    unawaited(WakelockPlus.enable());
  }

  Future<void> _setup() async {
    try {
      await _model.initialize();
      final first = await _pages.get(0);
      if (widget.score.pageCount > 1) await _pages.get(1);
      if (!mounted || _closing) return;
      setState(() {
        _page = first;
        _gate = LineGate(first.layout.rows.length, stableFrames: 5);
        _ready = true;
        _busy = false;
        _status = '已准备前两页。点击开始监听；也可点击谱行校准起点。';
      });
    } catch (e) {
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _status = '准备失败：$e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_pause('应用中断，已暂停；请手动继续'));
    }
  }

  @override
  void dispose() {
    _closing = true;
    _listening = false;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdown());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _mic.stop();
    await _starting;
    await _mic.stop();
    await _setupFuture;
    await _worker;
    await _mic.dispose();
    await _model.close();
  }

  Future<void> _pause([String message = '已暂停，页面保持显示']) async {
    if (_closing) return;
    _epoch++;
    _listening = false;
    _queue.clear();
    if (mounted) {
      setState(() {
        _busy = true;
        _status = message;
      });
    }
    await _mic.stop();
    await _starting;
    await _mic.stop();
    await _worker;
    _gate?.breakEvidence();
    if (mounted && !_closing) setState(() => _busy = false);
  }

  Future<void> _start() {
    if (_starting != null) return _starting!;
    final started = _startListening();
    _starting = started;
    return started.whenComplete(() => _starting = null);
  }

  Future<void> _startListening() async {
    if (!_ready || _busy || _listening || _closing) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _status = '正在启动收音…';
    });
    try {
      await _model.reset();
      if (!mounted || epoch != _epoch) return;
      _queue.clear();
      _frameCount = 0;
      final spectrum = LineSpectrum(_model.filterbank, (frame) {
        if (!mounted ||
            !_listening ||
            _closing ||
            _swapping ||
            epoch != _epoch) {
          return;
        }
        if (_queue.length >= 8) {
          _listening = false;
          unawaited(_pause('设备推理跟不上实时收音，已暂停自动翻页。可继续手动翻页。'));
          return;
        }
        _queue.add(frame);
        _worker ??= _drain(epoch);
      });
      _listening = true;
      await _mic.arm(
        onStart: () {},
        onMeter: (_, _) {},
        onPcm: spectrum.add,
        onError: (e) {
          if (mounted && epoch == _epoch) unawaited(_pause('收音中断：$e'));
        },
      );
      if (mounted && epoch == _epoch) {
        setState(() => _status = '监听中：等待稳定确认当前谱行');
      }
    } catch (e) {
      if (mounted && epoch == _epoch) {
        _listening = false;
        setState(() => _status = '无法开始：$e');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _drain(int epoch) async {
    try {
      while (_queue.isNotEmpty && _listening && !_closing && epoch == _epoch) {
        final frame = _queue.removeFirst(), page = _page!, gate = _gate!;
        final watch = Stopwatch()..start();
        final estimate = await _model.predict(frame, page, gate.current);
        watch.stop();
        if (!mounted || _closing || epoch != _epoch || !_listening) return;
        _latency = watch.elapsedMicroseconds / 1000;
        _rms = frame.rms;
        _frameCount++;
        if (frame.rms < 0.008) {
          gate.breakEvidence();
          if (_frameCount % 10 == 0) setState(() => _status = '收音较弱，保持当前页');
          continue;
        }
        if (estimate == null) {
          // Image model runs on alternate audio frames; those gaps are expected.
          if (_frameCount.isEven) gate.breakEvidence();
          continue;
        }
        final turn = gate.add(estimate.row, audioValid: true);
        setState(
          () => _status =
              '候选第 ${estimate.row + 1} 行 · 已确认 ${gate.current >= 0 ? gate.current + 1 : '—'} 行',
        );
        if (_tail != null && gate.current >= 1) setState(() => _tail = null);
        if (turn &&
            _automatic &&
            page.layout.rows.length > 1 &&
            page.index < widget.score.pageCount - 1) {
          await _advance(epoch);
        }
      }
    } catch (e) {
      _listening = false;
      _queue.clear();
      _epoch++;
      unawaited(_mic.stop());
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _status = '跟随已暂停：$e';
        });
      }
    } finally {
      _worker = null;
    }
  }

  Future<void> _advance(int epoch) async {
    _swapping = true;
    _queue.clear();
    try {
      final previous = _page!, next = await _pages.get(_page!.index + 1);
      if (!mounted || _closing || epoch != _epoch || !_listening) return;
      await _model.reset();
      if (!mounted || _closing || epoch != _epoch) return;
      setState(() {
        _tail = previous;
        _page = next;
        _gate = LineGate(next.layout.rows.length, stableFrames: 5);
        _frameCount = 0;
        _status = '已进入最后一行：显示下一页，并保留上一行';
      });
      _pages.retain(next.index);
      if (next.index + 1 < widget.score.pageCount) {
        unawaited(
          _pages
              .get(next.index + 1)
              .then<void>(
                (_) {},
                onError: (Object e, StackTrace s) {
                  if (mounted && !_closing) {
                    setState(() => _status = '后续页准备失败，当前页仍可阅读：$e');
                  }
                },
              ),
        );
      }
    } finally {
      _swapping = false;
    }
  }

  Future<void> _manualPage(int index) async {
    if (_busy || _closing) return;
    await _pause('正在准备页面…');
    if (!mounted || _closing) return;
    setState(() => _busy = true);
    try {
      final next = await _pages.get(index);
      if (!mounted || _closing) return;
      setState(() {
        _page = next;
        _tail = null;
        _gate = LineGate(next.layout.rows.length, stableFrames: 5);
        _automatic = false;
        _status = '已手动接管。点击实际谱行，再开始监听可恢复自动。';
      });
    } catch (e) {
      if (mounted) setState(() => _status = '页面准备失败：$e');
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  Future<void> _seek(int row) async {
    if (_busy || _closing) return;
    await _pause();
    if (!mounted || _closing) return;
    setState(() {
      _gate!.seek(row);
      _automatic = true;
      _status = '起点设为第 ${row + 1} 行，点击开始监听';
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '谱行跟随原型${page == null ? '' : ' · ${page.index + 1}/${widget.score.pageCount} 页'}',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_tail != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('上一页最后一行'),
                  TextButton(
                    onPressed: () => setState(() => _tail = null),
                    child: const Text('收起'),
                  ),
                ],
              ),
              Expanded(flex: 2, child: FinalRowStrip(page: _tail!)),
              const Divider(height: 2),
            ],
            Expanded(
              flex: 5,
              child: page == null
                  ? Center(
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.error_outline, size: 48),
                    )
                  : LinePageView(
                      page: page,
                      row: _gate?.current ?? -1,
                      onRow: _busy ? null : _seek,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Text(_status, maxLines: 3, textAlign: TextAlign.center),
            ),
            if (_listening)
              Text(
                '推理 ${_latency.toStringAsFixed(0)} ms · 队列 ${_queue.length}/8 · 音量 ${_rms.toStringAsFixed(3)}',
                style: const TextStyle(fontSize: 11),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                IconButton(
                  tooltip: '上一页',
                  onPressed: !_busy && page != null && page.index > 0
                      ? () => _manualPage(page.index - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                FilledButton.icon(
                  onPressed: !_ready || _busy
                      ? null
                      : (_listening ? _pause : _start),
                  icon: Icon(_listening ? Icons.pause : Icons.mic),
                  label: Text(_listening ? '暂停' : '开始监听'),
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed:
                      !_busy &&
                          page != null &&
                          page.index < widget.score.pageCount - 1
                      ? () => _manualPage(page.index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('自动'),
                    Switch(
                      value: _automatic,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _automatic = v;
                              if (_gate != null) {
                                final current = _gate!.current;
                                _gate = LineGate(
                                  _gate!.rowCount,
                                  stableFrames: 5,
                                );
                                if (current >= 0) _gate!.seek(current);
                              }
                            }),
                    ),
                  ],
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Text(
                '实验原型 · 仅本机收音分析，不保存录音。适用于清晰的钢琴双谱表；跳奏／反复请点击谱行重新定位。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
