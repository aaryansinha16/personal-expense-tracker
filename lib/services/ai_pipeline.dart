import 'ai_triage.dart';

class PipelineProgress {
  final int batchIndex;
  final int totalBatches;
  final int itemsDone;
  final int itemsTotal;
  final double usdSpent;
  const PipelineProgress({
    required this.batchIndex,
    required this.totalBatches,
    required this.itemsDone,
    required this.itemsTotal,
    required this.usdSpent,
  });
}

class PipelineResult {
  final List<AiDecision> decisions;
  final double usdSpent;
  final int itemsProcessed;
  final String? error;
  PipelineResult({
    required this.decisions,
    required this.usdSpent,
    required this.itemsProcessed,
    this.error,
  });
}

/// Batch-aware wrapper around AiTriageService. Splits large lists of items
/// into LLM calls of [batchSize] each, streams progress, aggregates cost.
class AiPipeline {
  final AiTriageService _ai;
  final int batchSize;

  AiPipeline({AiTriageService? service, this.batchSize = 20})
      : _ai = service ?? AiTriageService.instance;

  Future<PipelineResult> classifyAll(
    List<TriageItem> items, {
    required List<String> categories,
    void Function(PipelineProgress)? onProgress,
  }) async {
    if (items.isEmpty) {
      return PipelineResult(decisions: const [], usdSpent: 0, itemsProcessed: 0);
    }
    final decisions = <AiDecision>[];
    double totalUsd = 0;
    final totalBatches = (items.length + batchSize - 1) ~/ batchSize;

    for (var b = 0; b < totalBatches; b++) {
      final start = b * batchSize;
      final end = (start + batchSize).clamp(0, items.length);
      final batch = items.sublist(start, end);
      try {
        final res = await _ai.triage(batch, categories: categories);
        decisions.addAll(res.decisions);
        totalUsd += res.cost.usd;
      } catch (e) {
        // Return what we have so the caller can apply partial results, and
        // surface the error message so the UI can display it.
        return PipelineResult(
          decisions: decisions,
          usdSpent: totalUsd,
          itemsProcessed: decisions.length,
          error: e.toString(),
        );
      }
      onProgress?.call(PipelineProgress(
        batchIndex: b + 1,
        totalBatches: totalBatches,
        itemsDone: decisions.length,
        itemsTotal: items.length,
        usdSpent: totalUsd,
      ));
    }

    return PipelineResult(
      decisions: decisions,
      usdSpent: totalUsd,
      itemsProcessed: decisions.length,
    );
  }

  /// Rough pre-sync estimate. Numbers sourced from real batch measurements:
  /// SMS ~\$0.00035/item, Email ~\$0.00067/item, both with cache-hit system
  /// prompt on batches 2+.
  static double estimateUsd({required int smsCount, required int emailCount}) {
    return smsCount * 0.00035 + emailCount * 0.00067;
  }

  /// Same, formatted as an approximate rupee figure at an assumed 83 INR/USD.
  static int estimateInrRounded({required int smsCount, required int emailCount}) {
    return (estimateUsd(smsCount: smsCount, emailCount: emailCount) * 83).ceil();
  }
}
