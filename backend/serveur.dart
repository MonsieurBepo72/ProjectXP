// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final String? apiKey =
      Platform.environment['OPENAI_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    print('ERREUR : OPENAI_API_KEY est absente.');
    print(
      'PowerShell : \$env:OPENAI_API_KEY="ta_cle"',
    );
    exit(1);
  }

  final server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    8080,
  );

  print('====================================');
  print(' PROJECT XP - Avatar Server');
  print(' http://127.0.0.1:8080');
  print('====================================');

  await for (final request in server) {
    if (request.method == 'POST' &&
        request.uri.path == '/avatar/generate') {
      await _generateAvatar(
        request,
        apiKey,
      );

      continue;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'error': 'Route inexistante.',
        }),
      );

    await request.response.close();
  }
}

Future<void> _generateAvatar(
  HttpRequest request,
  String apiKey,
) async {
  try {
    final String body =
        await utf8.decoder.bind(request).join();

    final Map<String, dynamic> input =
        jsonDecode(body);

    final String? imageBase64 =
        input['imageBase64'] as String?;

    final String mimeType =
        input['mimeType'] as String? ??
            'image/jpeg';

    if (imageBase64 == null ||
        imageBase64.isEmpty) {
      await _sendError(
        request,
        HttpStatus.badRequest,
        'Aucune photo reçue.',
      );

      return;
    }

    print('Photo reçue.');
    print('Génération de l’avatar...');

    final HttpClient client = HttpClient();

    final HttpClientRequest openAiRequest =
        await client.postUrl(
      Uri.parse(
        'https://api.openai.com/v1/responses',
      ),
    );

    openAiRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $apiKey',
    );

    openAiRequest.headers.contentType =
        ContentType.json;

    const String prompt = '''
Transform the person in the reference photo into a Project XP fantasy gaming adventurer avatar.

IMPORTANT:
- Preserve the person's recognizable facial identity and important facial features.
- Keep their natural face shape, approximate hairstyle, hair color, facial hair and glasses when visible.
- Do not change the person's apparent identity.
- Semi-realistic stylized fantasy illustration, not photorealistic.
- Approximately 70% medieval fantasy RPG and 30% subtle gaming/geek influence.
- Warm, heroic and friendly appearance.
- Bust portrait from chest or waist upward.
- Looking toward the viewer.
- Natural relaxed pose.
- Detailed leather, cloth and subtle metal fantasy clothing.
- Small discreet gaming references such as a D20 pin, tiny XP medallion or subtle controller engraving.
- No large modern logos.
- No written text.
- No frame.
- No scenery.
- Transparent background.
- The result must be suitable as a profile avatar in a fantasy gaming social app.
''';

    openAiRequest.write(
      jsonEncode({
        'model': 'gpt-5',
        'input': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text': prompt,
              },
              {
                'type': 'input_image',
                'image_url':
                    'data:$mimeType;base64,$imageBase64',
                'detail': 'high',
              },
            ],
          },
        ],
        'tools': [
          {
            'type': 'image_generation',
            'model': 'gpt-image-1',
            'action': 'edit',
            'input_fidelity': 'high',
            'background': 'transparent',
            'quality': 'high',
            'size': '1024x1024',
          },
        ],
        'tool_choice': {
          'type': 'image_generation',
        },
      }),
    );

    final HttpClientResponse openAiResponse =
        await openAiRequest.close();

    final String openAiBody =
        await utf8.decoder
            .bind(openAiResponse)
            .join();

    client.close();

    if (openAiResponse.statusCode < 200 ||
        openAiResponse.statusCode >= 300) {
      print('Erreur OpenAI :');
      print(openAiBody);

      await _sendError(
        request,
        HttpStatus.badGateway,
        'La génération a échoué.',
      );

      return;
    }

    final Map<String, dynamic> responseJson =
        jsonDecode(openAiBody);

    final List<dynamic> output =
        responseJson['output'] as List<dynamic>;

    String? generatedImage;

    for (final dynamic item in output) {
      if (item is Map<String, dynamic> &&
          item['type'] ==
              'image_generation_call') {
        generatedImage =
            item['result'] as String?;

        if (generatedImage != null) {
          break;
        }
      }
    }

    if (generatedImage == null) {
      await _sendError(
        request,
        HttpStatus.badGateway,
        'OpenAI n’a retourné aucune image.',
      );

      return;
    }

    print('Avatar généré !');

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'imageBase64': generatedImage,
        }),
      );

    await request.response.close();
  } catch (error, stackTrace) {
    print(error);
    print(stackTrace);

    await _sendError(
      request,
      HttpStatus.internalServerError,
      'Erreur interne du serveur.',
    );
  }
}

Future<void> _sendError(
  HttpRequest request,
  int statusCode,
  String message,
) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'error': message,
      }),
    );

  await request.response.close();
}