import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/line_following/line_pages.dart';

class LinePageView extends StatelessWidget {
  const LinePageView({
    super.key,
    required this.page,
    this.row = -1,
    this.onRow,
  });
  final PreparedLinePage page;
  final int row;
  final ValueChanged<int>? onRow;
  @override
  Widget build(BuildContext context) => InteractiveViewer(
    key: ValueKey(page.path),
    minScale: 1,
    maxScale: 4,
    child: Center(
      child: AspectRatio(
        aspectRatio: 835 / 1181,
        child: LayoutBuilder(
          builder: (context, size) => Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(page.path), fit: BoxFit.fill),
              for (var i = 0; i < page.layout.rows.length; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: page.layout.rows[i].top * size.maxHeight,
                  height:
                      (page.layout.rows[i].bottom - page.layout.rows[i].top) *
                      size.maxHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onRow == null ? null : () => onRow!(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == row
                            ? Colors.teal.withValues(alpha: 0.12)
                            : Colors.transparent,
                        border: Border.all(
                          color: i == page.layout.rows.length - 1
                              ? Colors.orange
                              : Colors.teal.withValues(alpha: 0.35),
                          width: i == row ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.topLeft,
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.8),
                        child: Text(
                          '第 ${i + 1} 行',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black,
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

class FinalRowStrip extends StatelessWidget {
  const FinalRowStrip({super.key, required this.page});
  final PreparedLinePage page;
  @override
  Widget build(BuildContext context) {
    final row = page.layout.rows.last;
    final top = (row.top - 0.04).clamp(0.0, 1.0),
        bottom = (row.bottom + 0.04).clamp(0.0, 1.0);
    return Center(
      child: AspectRatio(
        aspectRatio: 835 / (1181 * (bottom - top)),
        child: LayoutBuilder(
          builder: (context, size) => ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: -top * size.maxHeight / (bottom - top),
                  height: size.maxHeight / (bottom - top),
                  child: Image.file(File(page.path), fit: BoxFit.fill),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
