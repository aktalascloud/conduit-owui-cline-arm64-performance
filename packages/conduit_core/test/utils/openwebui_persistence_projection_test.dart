import 'dart:convert';

import 'package:conduit_core/services/structured_output.dart';
import 'package:conduit_core/services/structured_output_renderer.dart';
import 'package:conduit_core/utils/openwebui_message_payload.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> output(String answer) => [
  {
    'type': 'function_call',
    'call_id': 'call',
    'name': 'lookup',
    'arguments': '{}',
    'status': 'completed',
  },
  {
    'type': 'function_call_output',
    'call_id': 'call',
    'output': 'synthetic result',
  },
  {
    'type': 'message',
    'content': [
      {'type': 'output_text', 'text': answer},
    ],
  },
];
String display(List<Map<String, dynamic>> value) =>
    renderStructuredOutputBlocks(parseOpenWebUIStructuredOutput(value));

void main() {
  const literal =
      '<details type="tool_calls"><summary>Example</summary>literal</details>';
  const answer = 'Answer.\n```html\n$literal\n```\n\n$literal';

  test('verified display projects to exact source text including code and literal HTML', () {
    final raw = output(answer);
    final rendered = display(raw);
    expect(rendered, isNot(answer));
    expect(projectOpenWebUiContent('assistant', rendered, raw), answer);
  });

  test(
    'user text is never projected even when it equals a display projection',
    () {
      final raw = output(answer);
      expect(projectOpenWebUiContent('user', display(raw), raw), display(raw));
      expect(projectOpenWebUiContent('user', literal, null), literal);
    },
  );

  test(
    'missing output and mismatched partial streaming text stay verbatim',
    () {
      final raw = output(answer);
      final partial = '${display(raw)}\nnew unfinished suffix';
      expect(projectOpenWebUiContent('assistant', partial, raw), partial);
      expect(projectOpenWebUiContent('assistant', literal, null), literal);
      expect(projectOpenWebUiContent('assistant', literal, []), literal);
    },
  );

  test('source-owned semantic HTML without generated sections is retained', () {
    final raw = [
      {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': literal},
        ],
      },
    ];
    final rendered = display(raw);
    expect(projectOpenWebUiContent('assistant', rendered, raw), rendered);
  });

  test('whole blob projection preserves output, branches, versions, fields and input', () {
    final raw = output(answer);
    final message = {
      'id': 'a',
      'role': 'assistant',
      'content': display(raw),
      'output': raw,
      'versions': [
        {'content': display(raw), 'output': raw, 'custom': 7},
      ],
      'unknown': {'keep': true},
    };
    final user = {
      'id': 'u',
      'role': 'user',
      'content': literal,
      'versions': [
        {'content': literal},
      ],
      'output': raw,
    };
    final blob = <String, dynamic>{
      'history': {
        'currentId': 'a',
        'messages': {'a': message, 'u': user},
        'unknown': 8,
      },
      'messages': [user, message],
      'params': {'temperature': 0.7},
      'acl': {'keep': true},
      'custom': 9,
    };
    final before = jsonEncode(blob);
    final projected = projectOpenWebUiChatBlob(blob);
    final history = projected['history']['messages'] as Map;
    expect(history['a']['content'], answer);
    expect(history['a']['versions'][0]['content'], answer);
    expect(history['a']['output'], raw);
    expect(history['a']['unknown'], {'keep': true});
    expect(history['u'], user);
    expect(projected['params'], blob['params']);
    expect(projected['acl'], blob['acl']);
    expect((projected['messages'] as List)[1]['content'], answer);
    expect(jsonEncode(blob), before);
    expect(projectOpenWebUiChatBlob(projected), projected);
  });

  test('malformed and multimodal content shapes remain untouched', () {
    final blob = <String, dynamic>{
      'history': 'legacy',
      'messages': [
        null,
        7,
        {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': literal},
          ],
          'output': output(answer),
        },
      ],
    };
    expect(projectOpenWebUiChatBlob(blob), blob);
  });

  test('tool-only reply keeps protocol history while dropping only generated display', () {
    final raw = output('')..removeLast();
    final blob = <String, dynamic>{
      'messages': [
        {'role': 'assistant', 'content': display(raw), 'output': raw},
      ],
    };
    final projected = projectOpenWebUiChatBlob(blob);
    expect(projected['messages'][0]['content'], '');
    expect(projected['messages'][0]['output'], raw);
    expect(blob['messages'][0]['content'], isNotEmpty);
  });
}
