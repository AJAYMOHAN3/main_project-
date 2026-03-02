import 'package:flutter/material.dart';
import 'package:main_project/main.dart';
import 'dag_engine.dart';
import 'package:main_project/tenant/tenant.dart';

class DagVisualizerPage extends StatelessWidget {
  const DagVisualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Immutable Audit Ledger",
                  onBack: () => Navigator.pop(context),
                ),

                // Explanatory Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black.withValues(alpha: 0.6),
                  width: double.infinity,
                  child: const Text(
                    "DAG Nodes.",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

                // DAG Network Canvas
                Expanded(
                  child: AnimatedBuilder(
                    animation: DagLedger.instance,
                    builder: (context, _) => InteractiveViewer(
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.1,
                      maxScale: 2.0,
                      child: Padding(
                        padding: const EdgeInsets.all(80.0),
                        child: CustomPaint(
                          size: const Size(3000, 1500),
                          painter: DagPainter(DagLedger.instance.allNodes),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DagPainter extends CustomPainter {
  final List<DagNode> nodes;
  DagPainter(this.nodes);

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final paintLine = Paint()
      ..color = Colors.tealAccent.withValues(alpha: 0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintNode = Paint()..color = Colors.tealAccent;
    final paintGenesis = Paint()..color = Colors.orangeAccent;

    final Map<int, List<DagNode>> depthMap = {};
    for (var node in nodes) {
      depthMap.putIfAbsent(node.depth, () => []).add(node);
    }

    final Map<String, Offset> positions = {};
    const double nodeSpacingX = 140.0;
    const double nodeSpacingY = 90.0;

    for (var depth in depthMap.keys) {
      final nodesAtDepth = depthMap[depth]!;
      final double startY =
          (size.height / 2) - ((nodesAtDepth.length - 1) * nodeSpacingY / 2);
      for (int i = 0; i < nodesAtDepth.length; i++) {
        positions[nodesAtDepth[i].txId] = Offset(
          50.0 + (depth * nodeSpacingX),
          startY + (i * nodeSpacingY),
        );
      }
    }

    for (var node in nodes) {
      final start = positions[node.txId]!;
      for (var parentId in node.parents) {
        final end = positions[parentId];
        if (end != null) {
          final path = Path()
            ..moveTo(start.dx, start.dy)
            ..cubicTo(
              start.dx - 40,
              start.dy,
              end.dx + 40,
              end.dy,
              end.dx,
              end.dy,
            );
          canvas.drawPath(path, paintLine);
        }
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var node in nodes) {
      final pos = positions[node.txId]!;
      canvas.drawCircle(pos, 15, node.depth == 0 ? paintGenesis : paintNode);

      textPainter.text = TextSpan(
        text: node.data.length > 15
            ? "${node.data.substring(0, 15)}..."
            : node.data,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy + 20),
      );

      textPainter.text = TextSpan(
        text: node.txId.substring(0, 6),
        style: const TextStyle(color: Colors.white54, fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - 32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DagPainter oldDelegate) => true;
}
