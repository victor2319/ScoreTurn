import 'dart:io';

import 'package:flutter/material.dart';

import '../core/score_document.dart';

class AnnotatedPage extends StatelessWidget {
  const AnnotatedPage({
    super.key,
    required this.path,
    required this.document,
    required this.page,
    this.active,
    this.onMeasure,
    this.showAll = true,
  });
  final String path;
  final ScoreDocument document;
  final int page;
  final int? active;
  final ValueChanged<int>? onMeasure;
  final bool showAll;
  @override
  Widget build(BuildContext context) {
    final geometry = document.pages[page];
    return InteractiveViewer(
      key: ValueKey('$path-$page'),
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: AspectRatio(
          aspectRatio: geometry.width / geometry.height,
          child: LayoutBuilder(
            builder: (context, size) => Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  fit: BoxFit.fill,
                  errorBuilder: (_, e, s) => Center(child: Text('图片读取失败：$e')),
                ),
                for (final measure in document.measures.where(
                  (m) => m.page == page,
                ))
                  if (showAll || active == measure.id)
                    Positioned(
                      left: measure.box[0] * size.maxWidth,
                      top: measure.box[1] * size.maxHeight,
                      width: (measure.box[2] - measure.box[0]) * size.maxWidth,
                      height:
                          (measure.box[3] - measure.box[1]) * size.maxHeight,
                      child: GestureDetector(
                        onTap: onMeasure == null
                            ? null
                            : () => onMeasure!(measure.id),
                        child: Container(
                          decoration: BoxDecoration(
                            color: active == measure.id
                                ? Colors.teal.withValues(alpha: 0.16)
                                : Colors.transparent,
                            border: Border.all(
                              width: active == measure.id ? 3 : 1,
                              color: document.turnAfter[page] == measure.id
                                  ? Colors.orange
                                  : Colors.teal,
                            ),
                          ),
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: Colors.white.withValues(alpha: 0.85),
                            child: Text(
                              '${measure.id + 1}${document.turnAfter[page] == measure.id ? ' ↪' : ''}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
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
