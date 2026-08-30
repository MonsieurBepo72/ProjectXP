// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int _serverPort = 8080;
const int _maxRequestBytes = 12 * 1024 * 1024;

const String _allowLanEnvironmentKey =
    'PROJECT_XP_DEV_SERVER_ALLOW_LAN';
const String _devTokenEnvironmentKey =
    'PROJECT_XP_DEV_SERVER_TOKEN';

Future<void> main() async {
  final String apiKey =
      (Platform.environment['OPENAI_API_KEY'] ?? '').trim();

  if (apiKey.isEmpty) {
    print('ERREUR : OPENAI_API_KEY est absente.');
    print(
      'PowerShell : \$env:OPENAI_API_KEY="ta_cle"',
    );
    exit(1);
  }

  final bool allowLan = _isEnabled(
    Platform.environment[_allowLanEnvironmentKey],
  );

  final String devToken =
      (Platform.environment[_devTokenEnvironmentKey] ?? '').trim();

  // Par défaut le serveur n'écoute QUE localhost.
  // Une exposition sur le LAN doit être explicitement activée et protégée.
  if (allowLan && devToken.length < 24) {
    print(
      'ERREUR : le mode LAN exige '
      '$_devTokenEnvironmentKey (24 caractères minimum).',
    );
    exit(1);
  }

  final InternetAddress bindAddress = allowLan
      ? InternetAddress.anyIPv4
      : InternetAddress.loopbackIPv4;

  final HttpServer server = await HttpServer.bind(
    bindAddress,
    _serverPort,
  );

  print('====================================');
  print(' PROJECT XP - Avatar Server (DEV)');
  print(
    allowLan
        ? ' LAN activé sur le port $_serverPort'
        : ' Local uniquement : http://127.0.0.1:$_serverPort',
  );
  print('====================================');

  await for (final HttpRequest request in server) {
    if (allowLan && !_hasValidDevToken(request, devToken)) {
      await _sendError(
        request,
        HttpStatus.unauthorized,
        'Requête de développement non autorisée.',
      );
      continue;
    }

    if (request.method == 'POST' &&
        request.uri.path == '/avatar/generate') {
      await _generateAvatar(
        request,
        apiKey,
      );
      continue;
    }

    await _sendError(
      request,
      HttpStatus.notFound,
      'Route inexistante.',
    );
  }
}

bool _isEnabled(String? value) {
  switch (value?.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
    default:
      return false;
  }
}

bool _hasValidDevToken(
  HttpRequest request,
  String expectedToken,
) {
  final String providedToken =
      (request.headers.value('x-project-xp-dev-token') ?? '').trim();

  return providedToken.isNotEmpty &&
      providedToken == expectedToken;
}

Future<void> _generateAvatar(
  HttpRequest request,
  String apiKey,
) async {
  try {
    if (request.contentLength > _maxRequestBytes) {
      await _sendError(
        request,
        HttpStatus.requestEntityTooLarge,
        'Image trop volumineuse.',
      );
      return;
    }

    final BytesBuilder requestBytes = BytesBuilder(copy: false);
    int receivedBytes = 0;

    await for (final List<int> chunk in request) {
      receivedBytes += chunk.length;

      if (receivedBytes > _maxRequestBytes) {
        await _sendError(
          request,
          HttpStatus.requestEntityTooLarge,
          'Image trop volumineuse.',
        );
        return;
      }

      requestBytes.add(chunk);
    }

    final String body = utf8.decode(
      requestBytes.takeBytes(),
    );

    final dynamic decodedInput = jsonDecode(body);

    if (decodedInput is! Map<String, dynamic>) {
      await _sendError(
        request,
        HttpStatus.badRequest,
        'Corps JSON invalide.',
      );
      return;
    }

    final Map<String, dynamic> input = decodedInput;

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