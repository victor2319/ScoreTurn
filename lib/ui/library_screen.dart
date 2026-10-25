import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/score.dart';
import '../core/score_library.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final ScoreLibrary _library = ScoreLibrary();
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _library.initialize();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _alert(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final selected = await FilePicker.pickFiles(type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
      if (selected.isEmpty) return;
      final pdfs = selected.where((f) => f.extension?.toLowerCase() == 'pdf').toList();
      final photos = selected.where((f) => f.extension?.toLowerCase() != 'pdf').toList();
      if (pdfs.isNotEmpty && photos.isNotEmpty) {
        throw StateError('请分两次导入 PDF 和图片，不要混选。');
      }
      if (pdfs.length > 1) {
        throw StateError('一次导入一份 PDF；多张图片可以一次选择并作为连续页面。');
      }
      for (final pdf in pdfs) {
        final bytes = await pdf.readAsBytes();
        if (bytes.length > 80 * 1024 * 1024) throw StateError('PDF 超过 80 MB。');
        await _library.importPdf(pdf.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''), bytes);
      }
      if (photos.isNotEmpty) {
        final pages = <List<int>>[];
        for (final photo in photos) {
          final bytes = await photo.readAsBytes();
          if (bytes.length > 40 * 1024 * 1024) throw StateError('单张图片超过 40 MB。');
          pages.add(bytes);
        }
        await _library.importImages('新乐谱 · ${DateTime.now().month}/${DateTime.now().day}',
            pages, photos.map((f) => f.extension ?? 'jpg').toList());
      }
      if (mounted) setState(() {});
      _alert('导入完成。进入乐谱后，请先检查 BPM 与每页最后小节。');
    } catch (e) {
      _alert('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(Score score) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除这份乐谱？'),
      content: Text('“${score.title}”将从本机删除，无法恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
      ],
    ));
    if (confirm == true) {
      await _library.delete(score);
      if (mounted) setState(() {});
    }
  }

  Future<void> _open(Score score) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(score: score, library: _library),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AutoScore'), actions: [
        IconButton(onPressed: _importing ? null : _import,
          tooltip: '导入 PDF／图片', icon: const Icon(Icons.add_circle_outline)),
      ]),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text('曲库读取失败：$_error'))
          : LayoutBuilder(builder: (context, constraints) => Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 940),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Text('我的曲谱', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('所有乐谱和设置保存在本机。演奏时无需网络。',
                  style: TextStyle(color: Color(0xFF586B79))),
                const SizedBox(height: 18),
                const Card(color: Color(0xFFE3F1EF), child: Padding(
                  padding: EdgeInsets.all(16), child: Row(children: [
                    Icon(Icons.info_outline, color: Color(0xFF007E80)),
                    SizedBox(width: 12),
                    Expanded(child: Text('实验版：默认按 BPM 计时翻页；尚不具备完整的音高跟谱与和声安全确认。正式演出请使用手动翻页。')),
                  ]))),
                const SizedBox(height: 12),
                for (final score in _library.scores)
                  Card(child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                    leading: CircleAvatar(backgroundColor: const Color(0xFFE4F4F2),
                      child: Icon(score.isPdf ? Icons.picture_as_pdf_outlined : Icons.collections_outlined,
                        color: const Color(0xFF007E80))),
                    title: Text(score.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${score.pageCount} 页 · ${score.bpm.toStringAsFixed(0)} BPM · ${score.beatsPerMeasure}/4 拍 · 本地'),
                    onTap: () => _open(score),
                    trailing: PopupMenuButton<String>(onSelected: (v) {
                      if (v == 'open') _open(score);
                      if (v == 'delete') _delete(score);
                    }, itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('打开曲谱')),
                      PopupMenuItem(value: 'delete', child: Text('删除本地乐谱')),
                    ]),
                  )),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: _importing ? null : _import,
                  icon: _importing ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_upload_outlined),
                  label: const Text('导入 PDF 或多张乐谱照片')),
              ]),
            ),
          )),
    );
  }
}
