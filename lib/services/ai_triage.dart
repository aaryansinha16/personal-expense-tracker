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
  final String? accountHint;
  final String confidence; // "high" | "medium" | "low"
  final String? reasoning;

  AiDecision({
    required this.isTransaction,
    this.amount,
    this.type,
    this.merchant,
    this.category,
    this.accountHint,
    required this.confidence,
    this.reasoning,
  });

  factory AiDecision.fromJson(Map<String, dynamic> j) => AiDecision(
        isTransaction: j['is_transaction'] == true,
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : null,
        type: j['type'] as String?,
        merchant: j['merchant'] as String?,
        category: j['category'] as String?,
        accountHint: j['account_hint'] as String?,
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

  /// Budget enough output tokens for the batch — a decision JSON runs
  /// 70–120 tokens, so 150/item + 500 overhead comfortably covers a
  /// verbose response without truncating mid-string. Capped at 8192
  /// (Haiku's ceiling).
  int _maxTokensFor(int itemCount) {
    final v = (itemCount * 150) + 500;
    if (v > 8192) return 8192;
    if (v < 1024) return 1024;
    return v;
  }

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
    List<String> accountHints = const [],
  }) async {
    if (items.isEmpty) {
      return AiTriageResult(
          decisions: const [], cost: const AiTriageCost(inputTokens: 0, outputTokens: 0));
    }

    final sys = _systemPrompt(categories, accountHints: accountHints);
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
      itemCount: items.length,
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
    // Strip optional markdown code fence (```json ... ```). Claude sometimes
    // wraps JSON in fences even when told not to.
    final cleaned = _stripCodeFence(text);
    final startIdx = cleaned.indexOf('[');
    final endIdx = cleaned.lastIndexOf(']');
    if (startIdx < 0 || endIdx < 0 || endIdx < startIdx) {
      // Response looked like JSON (had `[`) but got truncated before the
      // closing `]` — surface that specifically so the user knows it was
      // a token-limit issue, not Claude returning prose.
      final preview = cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
      if (startIdx >= 0 && endIdx < 0) {
        throw FormatException(
          'Claude response truncated before closing `]` '
          '(${cleaned.length} chars output). Usually means max_tokens was '
          'too small. First 200 chars: $preview',
        );
      }
      throw FormatException(
        'Claude returned non-JSON text (${cleaned.length} chars). '
        'First 200 chars: $preview',
      );
    }
    final arr = cleaned.substring(startIdx, endIdx + 1);
    final decoded = jsonDecode(arr);
    if (decoded is! List) {
      throw const FormatException('Claude response root was not a JSON array');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AiDecision.fromJson)
        .toList();
  }

  String _stripCodeFence(String text) {
    final t = text.trim();
    // ```json\n...\n```  or ```\n...\n```
    final fenceRe = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```\s*$',
        multiLine: true);
    final m = fenceRe.firstMatch(t);
    if (m != null) return m.group(1)!.trim();
    return t;
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
    int itemCount = 1,
  }) async {
    final key = await getApiKey();
    if (key == null) {
      throw StateError('Anthropic API key not configured');
    }
    final body = <String, Object?>{
      'model': await getModel(),
      'max_tokens': _maxTokensFor(itemCount),
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

  String _systemPrompt(
    List<String> categories, {
    List<String> accountHints = const [],
  }) {
    final catList = categories.map((c) => '"$c"').join(', ');
    final accountBlock = accountHints.isEmpty
        ? 'The user has not configured named accounts.'
        : 'The user\'s accounts:\n${accountHints.map((a) => '- $a').join('\n')}';
    return '''You are a financial transaction classifier for a personal expense tracker.

For each item you receive — an SMS or email snippet from a bank, card issuer, or merchant — decide whether it represents a real money event that belongs in the user's expense log. Extract the amount, direction, merchant, category, and (when possible) which of the user's accounts it came from.

Categories (pick exactly one or null): $catList

$accountBlock

Return a JSON array. Each item has the shape:
{
  "is_transaction": boolean,
  "amount": number | null,
  "type": "debit" | "credit" | "transfer" | null,
  "merchant": string | null,
  "category": string | null,
  "account_hint": string | null,
  "confidence": "high" | "medium" | "low",
  "reasoning": string
}

`account_hint`: if you can identify which of the user's accounts this came from (based on the last 4 digits mentioned in the text matching one of the accounts listed, or by issuer name), put the account's exact name. Otherwise null.

Rules:
- **OTP** messages, login codes, verification codes → is_transaction: false, confidence: high.
- **Promotional** / deal / newsletter / "offer ends soon" emails → false, high.
- **Delivery updates** (shipped, out for delivery, delivered) without payment wording → false, high.
- **Future payment notices** ("upcoming e-mandate", "will be debited on X", "scheduled auto-payment") → false, high.
- **Credit card bill payment** where the message says the payment was received on the user's own credit card (the other side of a bank debit) → is_transaction: false.
- **Credit card cash advance to a bank account** (e.g. "Rs 3000 debited from your HDFC CC, credited to your Axis savings account") → is_transaction: true, type: "transfer", category: "Transfer". This is an INTRA-ACCOUNT transfer — money moved between two of the user's own accounts, no expense happened.
- If you see a matching pair in the same batch (one CC debit + one bank credit for the same amount on the same day) both should be classified as "transfer" with the same reasoning.
- **Refund received** → is_transaction: true, type: "credit", category: best-fit.
- **Normal debit / purchase** → is_transaction: true, type: "debit", category: best-fit.
- **Salary / income** → is_transaction: true, type: "credit", category: "Income".
- Unsure? confidence: "low" with reasoning.
- Never invent amounts. No amount visible → return null and low confidence.

Return ONLY the raw JSON array. No prose. No markdown fences. Start with `[`, end with `]`.''';
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
