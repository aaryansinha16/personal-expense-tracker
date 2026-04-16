import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Decision returned by the LLM for a single queue item.
class AiDecision {
  final bool isTransaction;
  final double? amount;
  final String? type; // "debit" | "credit" | "transfer"
  final String? merchant;
  final String? category;
  final String confidence; // "high" | "medium" | "low"
  final String? reasoning;

  AiDecision({
    required this.isTransaction,
    this.amount,
    this.type,
    this.merchant,
    this.category,
    required this.confidence,
    this.reasoning,
  });

  factory AiDecision.fromJson(Map<String, dynamic> j) => AiDecision(
        isTransaction: j['is_transaction'] == true,
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : null,
        type: j['type'] as String?,
        merchant: j['merchant'] as String?,
        category: j['category'] as String?,
        confidence: (j['confidence'] as String?) ?? 'low',
        reasoning: j['reasoning'] as String?,
      );
}

class AiTriageCost {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;
  const AiTriageCost({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
  });

  /// Rough USD cost estimate at Haiku-class pricing ($1/MTok input,
  /// $5/MTok output, $0.10/MTok cache read, $1.25/MTok cache write).
  double get usd {
    return (inputTokens / 1e6) * 1.0 +
        (outputTokens / 1e6) * 5.0 +
        (cacheCreationInputTokens / 1e6) * 1.25 +
        (cacheReadInputTokens / 1e6) * 0.10;
  }
}

class AiTriageResult {
  final List<AiDecision> decisions;
  final AiTriageCost cost;
  AiTriageResult({required this.decisions, required this.cost});
}

/// Claude Haiku classifier for queue items. The user supplies their own
/// Anthropic API key; nothing is proxied through a server.
class AiTriageService {
  static final AiTriageService instance = AiTriageService._();
  AiTriageService._();

  static const _kApiKey = 'anthropic_api_key';
  static const _kModel = 'anthropic_model';
  static const _kCumulativeUsd = 'ai_triage_cum_usd';
  static const _kItemsTriaged = 'ai_triage_items_total';
  static const _defaultModel = 'claude-haiku-4-5';
  static const _maxTokens = 1024;

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final m = prefs.getString(_kModel);
    return (m == null || m.trim().isEmpty) ? _defaultModel : m.trim();
  }

  Future<void> setModel(String? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (model == null || model.trim().isEmpty) {
      await prefs.remove(_kModel);
    } else {
      await prefs.setString(_kModel, model.trim());
    }
  }

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString(_kApiKey);
    return (k == null || k.isEmpty) ? null : k;
  }

  Future<void> setApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.trim().isEmpty) {
      await prefs.remove(_kApiKey);
    } else {
      await prefs.setString(_kApiKey, key.trim());
    }
  }

  Future<double> getCumulativeUsd() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kCumulativeUsd) ?? 0;
  }

  Future<int> getItemsTriaged() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kItemsTriaged) ?? 0;
  }

  Future<void> _bumpTotals(double usd, int items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCumulativeUsd, await getCumulativeUsd() + usd);
    await prefs.setInt(_kItemsTriaged, await getItemsTriaged() + items);
  }

  /// Returns null on success, or a human-readable error string.
  Future<String?> testConnection() async {
    try {
      final res = await _callApi([
        _message(role: 'user', text: 'Reply with the single word OK.'),
      ]);
      final hasContent = (res['content'] as List?)?.isNotEmpty ?? false;
      if (!hasContent) return 'Empty response from Claude.';
      return null;
    } on ClaudeApiException catch (e) {
      return e.toString();
    } catch (e) {
      return e.toString();
    }
  }

  /// Diagnostic info the user can see to verify the saved key matches the
  /// one they pasted. Returns a map of: {length, prefix, suffix, model}.
  Future<Map<String, String>> keyDebugInfo() async {
    final key = await getApiKey();
    final model = await getModel();
    if (key == null) {
      return {'length': '0', 'prefix': '(none)', 'suffix': '(none)', 'model': model};
    }
    return {
      'length': key.length.toString(),
      'prefix': key.length >= 8 ? key.substring(0, 8) : key,
      'suffix': key.length >= 4 ? key.substring(key.length - 4) : key,
      'model': model,
    };
  }

  /// Classify a batch of queue items. Sends one request with all items
  /// serialized as a numbered list so we only pay the system prompt cost
  /// once.
  Future<AiTriageResult> triage(
    List<TriageItem> items, {
    required List<String> categories,
  }) async {
    if (items.isEmpty) {
      return AiTriageResult(
          decisions: const [], cost: const AiTriageCost(inputTokens: 0, outputTokens: 0));
    }

    final sys = _systemPrompt(categories);
    final body = StringBuffer();
    body.writeln(
      'Classify each of the ${items.length} items below. '
      'Reply with a JSON array of exactly ${items.length} objects, in the same order.',
    );
    body.writeln('Each object must match the schema in the system prompt.');
    for (var i = 0; i < items.length; i++) {
      body.writeln('\n--- ITEM ${i + 1} ---');
      body.writeln('source: ${items[i].source}');
      body.writeln('sender: ${items[i].sender}');
      if (items[i].subject != null && items[i].subject!.isNotEmpty) {
        body.writeln('subject: ${items[i].subject}');
      }
      final snippet = items[i].body.length > 1500
          ? '${items[i].body.substring(0, 1500)}…'
          : items[i].body;
      body.writeln('body: $snippet');
    }

    final response = await _callApi(
      [_message(role: 'user', text: body.toString())],
      system: sys,
    );

    final usage = response['usage'] as Map<String, dynamic>?;
    final cost = AiTriageCost(
      inputTokens: (usage?['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage?['output_tokens'] as num?)?.toInt() ?? 0,
      cacheCreationInputTokens:
          (usage?['cache_creation_input_tokens'] as num?)?.toInt() ?? 0,
      cacheReadInputTokens:
          (usage?['cache_read_input_tokens'] as num?)?.toInt() ?? 0,
    );

    final text = (response['content'] as List)
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();

    final decisions = _parseBatchDecisions(text, items.length);
    await _bumpTotals(cost.usd, items.length);
    return AiTriageResult(decisions: decisions, cost: cost);
  }

  List<AiDecision> _parseBatchDecisions(String text, int expectedCount) {
    final startIdx = text.indexOf('[');
    final endIdx = text.lastIndexOf(']');
    if (startIdx < 0 || endIdx < 0 || endIdx < startIdx) {
      throw FormatException(
        'Claude returned non-JSON text (${text.length} chars). '
        'First 200 chars: ${text.substring(0, text.length > 200 ? 200 : text.length)}',
      );
    }
    final arr = text.substring(startIdx, endIdx + 1);
    final decoded = jsonDecode(arr);
    if (decoded is! List) {
      throw const FormatException('Claude response root was not a JSON array');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AiDecision.fromJson)
        .toList();
  }

  Map<String, Object?> _message({required String role, required String text}) =>
      {
        'role': role,
        'content': [
          {'type': 'text', 'text': text}
        ],
      };

  Future<Map<String, dynamic>> _callApi(
    List<Map<String, Object?>> messages, {
    String? system,
  }) async {
    final key = await getApiKey();
    if (key == null) {
      throw StateError('Anthropic API key not configured');
    }
    final body = <String, Object?>{
      'model': await getModel(),
      'max_tokens': _maxTokens,
      'messages': messages,
    };
    if (system != null) {
      body['system'] = [
        // Prompt caching on the system prompt — saves ~90% on subsequent
        // identical requests inside the same session.
        {
          'type': 'text',
          'text': system,
          'cache_control': {'type': 'ephemeral'},
        }
      ];
    }
    final res = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode >= 400) {
      // Try to extract the human-readable error message Anthropic returns.
      String detail = res.body;
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['error'] is Map) {
          final err = j['error'] as Map;
          detail = '${err['type']}: ${err['message']}';
        }
      } catch (_) {}
      throw ClaudeApiException(res.statusCode, detail);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String _systemPrompt(List<String> categories) {
    final catList = categories.map((c) => '"$c"').join(', ');
    return '''You are a financial transaction classifier for a personal expense tracker.

For each item you receive — an SMS or email snippet from a bank, card issuer, or merchant — decide whether it represents a real money-out-of-user's-pocket event that belongs in their expense log. Extract the amount, direction, merchant, and category.

Categories (pick exactly one or null): $catList

Return a JSON array. Each item has the shape:
{
  "is_transaction": boolean,
  "amount": number | null,
  "type": "debit" | "credit" | "transfer" | null,
  "merchant": string | null,
  "category": string | null,
  "confidence": "high" | "medium" | "low",
  "reasoning": string
}

Rules:
- **OTP** messages, login codes, verification codes → is_transaction: false, confidence: high.
- **Promotional** / deal / newsletter / "offer ends soon" emails → false, high.
- **Delivery updates** (shipped, out for delivery, delivered) without payment wording → false, high.
- **Future payment notices** ("upcoming e-mandate", "will be debited on X", "scheduled auto-payment") → false, high.
- **Credit card bill payment** where the message says the payment was received on the user's own credit card (the other side of a bank debit) → is_transaction: false (so it doesn't double-count), category: "Transfer", reasoning: explain.
- **Refund received** → is_transaction: true, type: "credit", category: best-fit.
- **Normal debit / purchase** → is_transaction: true, type: "debit", category: best-fit.
- **Salary / income** → is_transaction: true, type: "credit", category: "Income".
- If you're unsure whether it's a real transaction, set confidence: "low" and reasoning that explains the ambiguity.
- Never invent amounts. If no amount is clearly the transaction amount, return null and low confidence.

Return ONLY the JSON array, no prose.''';
  }
}

class ClaudeApiException implements Exception {
  final int statusCode;
  final String detail;
  ClaudeApiException(this.statusCode, this.detail);
  @override
  String toString() => 'Claude API error $statusCode: $detail';
}

class TriageItem {
  final int queueId;
  final String source; // "sms" | "email"
  final String sender;
  final String? subject;
  final String body;
  // For fresh SMS/email pulled from inbox (not yet in the queue): the
  // external identifier we'd mark as processed AFTER the decision is applied.
  // For SMS: the djb2 hash of (sender|body|date). For email: Gmail message ID.
  final String? sourceId;
  // When this item came from a fresh pull (not the review queue), the
  // original timestamp of the source. Used as the transaction date.
  final DateTime? sourceDate;
  final String? sourceAccount;

  TriageItem({
    required this.queueId,
    required this.source,
    required this.sender,
    this.subject,
    required this.body,
    this.sourceId,
    this.sourceDate,
    this.sourceAccount,
  });
}
