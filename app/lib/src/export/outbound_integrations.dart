import 'dart:convert';
import 'dart:io';

import 'package:transcript_core/transcript_core.dart';

class OutboundIntegrationException implements Exception {
  const OutboundIntegrationException(this.message, [this.remedy]);

  final String message;
  final String? remedy;

  @override
  String toString() => message;
}

/// Posts a structured note to a user-owned webhook or Notion database.
class OutboundIntegrations {
  const OutboundIntegrations({HttpClient Function()? client})
      : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  Future<void> postWebhook({
    required String url,
    required NoteDocument note,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const OutboundIntegrationException(
        'The webhook URL is not valid.',
        'Paste a full https URL in Settings.',
      );
    }
    await _postJson(uri, note.toJson());
  }

  Future<void> postNotionPage({
    required String token,
    required String databaseId,
    required NoteDocument note,
  }) async {
    if (token.trim().isEmpty || databaseId.trim().isEmpty) {
      throw const OutboundIntegrationException(
        'Notion is not configured.',
        'Add a Notion token and database ID in Settings.',
      );
    }
    await _postJson(
      Uri.parse('https://api.notion.com/v1/pages'),
      {
        'parent': {'database_id': databaseId.trim()},
        'properties': {
          'Name': {
            'title': [
              {
                'text': {'content': _clip(note.meta.title, 2000)},
              }
            ],
          },
        },
        'children': [
          {
            'object': 'block',
            'type': 'paragraph',
            'paragraph': {
              'rich_text': [
                {
                  'type': 'text',
                  'text': {'content': _clip(note.meta.summary, 2000)},
                }
              ],
            },
          },
        ],
      },
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
        'Notion-Version': '2022-06-28',
      },
    );
  }

  Future<void> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final client = _client();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OutboundIntegrationException(
          'The export could not be delivered.',
          'The destination returned HTTP ${response.statusCode}.',
        );
      }
    } on OutboundIntegrationException {
      rethrow;
    } on Object catch (error) {
      throw OutboundIntegrationException(
        'The export could not be delivered.',
        error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
