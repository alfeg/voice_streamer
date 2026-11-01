import 'dart:async';
import 'dart:convert';

import 'package:kolibri/kolibri.dart';

import '../core/cache/self_presence.dart';
import '../core/config/config.dart';
import '../core/config/countries.dart';
import '../core/config/komet_settings.dart';
import '../core/config/proxy_config.dart';
import '../core/protocol/opcode_map.dart';
import '../core/protocol/packet.dart';
import '../core/storage/device_identity.dart';
import '../core/storage/spoofing_service.dart';
import '../core/transport/dispatcher.dart';
import '../core/transport/traffic_monitor.dart';
import '../core/utils/debug_session_log.dart';
import '../core/utils/logger.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'dart:io';

enum SessionState { disconnected, connecting, connected, online }

/// Клиент API.
///
/// Сокет, фрейминг, MsgPack и сжатие живут в Rust-ядре kolibri; здесь —
/// хэндшейк со спуфом, жизненный цикл сессии и реконнект.
class Api {
  KolibriSession? _session;
  final PacketDispatcher _dispatcher = PacketDispatcher();
  StreamSubscription<(int, Map<String, dynamic>)>? _pushSub;
  StreamSubscription<WireLogEvent>? _wireLogSub;

  SessionState _sessionState = SessionState.disconnected;
  final _stateController = StreamController<SessionState>.broadcast();
  final _sessionExpiredController =
      StreamController<SessionExpiredException>.broadcast();
  final _handshakeSuccessController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  Map<dynamic, dynamic>? _userAgent;

  Map<dynamic, dynamic>? get userAgent => _userAgent;

  int? _callsSeed;
  String? _deviceId;
  String _architecture = SpoofingService.defaultArchitecture;

  int? get callsSeed => _callsSeed;
  String? get deviceId => _deviceId;
  String get architecture => _architecture;

  String? spoofScope;

  static bool _tzInitialized = false;

  List<CountryName>? _registrationCountries;

  List<CountryName> get registrationCountries =>
      _registrationCountries ?? allCountries;

  Stream<SessionState> get stateStream => _stateController.stream;
  Stream<SessionExpiredException> get sessionExpiredStream =>
      _sessionExpiredController.stream;
  Stream<String> get handshakeSuccessStream =>
      _handshakeSuccessController.stream;
  Stream<String> get errorStream => _errorController.stream;
  SessionState get state => _sessionState;

  Timer? _livenessTimer;
  Timer? _reconnectTimer;
  Timer? _connectWatchdog;
  int _connectGen = 0;
  int _reconnectAttempts = 0;
  bool _autoReconnect = false;
  int _sessionEpoch = 0;
  bool? _lastInteractive;
  bool _willAuthenticate = false;
  bool _suppressReconnectLogin = false;

  bool get isAuthenticatedHandshake => _willAuthenticate;

  static const Duration _connectWatchdogTimeout = Duration(seconds: 75);
  static const Duration _endpointTimeout = Duration(seconds: 5);
  static const Duration _livenessInterval = Duration(seconds: 5);

  int get sessionEpoch => _sessionEpoch;

  // Публичное API

  /// Подключается к серверу и шлёт хэндшейк.
  ///
  /// [authenticated] выбирает версию хэндшейка: `true` — боевая под вход по
  /// токену, `false` — pre-login без токена, `null` — прежний режим.
  Future<void> connect({bool? authenticated}) async {
    if (authenticated != null) _willAuthenticate = authenticated;
    if (_sessionState != SessionState.disconnected) {
      logger.i('connect пропущен: состояние ${_sessionState.name}');
      return;
    }
    _autoReconnect = true;
    final gen = ++_connectGen;
    _setSessionState(SessionState.connecting);
    logger.i('connect: старт (поколение $gen)');
    _armConnectWatchdog(gen);

    KolibriSession? built;
    try {
      ({String host, int port}) endpoint;
      try {
        endpoint = await ServerConfig.loadEndpoint().timeout(_endpointTimeout);
      } catch (e) {
        logger.w('connect: loadEndpoint завис/упал ($e) — дефолтный endpoint');
        endpoint = (
          host: ServerConfig.defaultHost,
          port: ServerConfig.defaultPort,
        );
      }
      if (gen != _connectGen) return;

      final (session, wireLog) = await _openSession(endpoint);
      built = session;
      if (gen != _connectGen) return;

      logger.i('connect: endpoint ${endpoint.host}:${endpoint.port}');
      _session = session;
      _wireLogSub?.cancel();
      _wireLogSub = wireLog.listen(_onWireLog);
      _pushSub?.cancel();
      _pushSub = session.pushesMap().listen(_onPush);
      TrafficMonitor.instance.recordEvent(
        'connect',
        endpoint: '${endpoint.host}:${endpoint.port}',
      );

      _setSessionState(SessionState.connected);
      _reconnectAttempts = 0;

      HandshakeInfo info;
      try {
        logger.i('connect: отправляю хэндшейк');
        info = await session.connect();
      } catch (e) {
        if (gen != _connectGen) return;
        await _handleConnectFailure(e, phase: 'Ошибка хэндшейка');
        return;
      }
      if (gen != _connectGen) return;

      _callsSeed = info.callsSeed?.toInt();
      _registrationCountries = _parseRegistrationCountries(info.payloadMap);
      _sessionState = SessionState.online;
      _sessionEpoch++;
      _cancelConnectWatchdog();
      _startLiveness();
      logger.i('Сессия онлайн, хэндшейк ок');
      if (_onReconnectCallback != null && !_suppressReconnectLogin) {
        try {
          await _onReconnectCallback!();
        } catch (e) {
          logger.w('Авто-логин при хэндшейке не удался: $e');
        }
      }
      if (gen != _connectGen) return;
      if (_sessionState == SessionState.online) {
        _stateController.add(SessionState.online);
        _handshakeSuccessController.add(info.deviceName ?? 'Unknown');
      }
    } catch (e, st) {
      logger.e('connect: непредвиденная ошибка: $e\n$st');
      if (gen == _connectGen) await _resetStuckConnect(gen);
    } finally {
      if (built != null && !identical(_session, built)) _releaseSession(built);
    }
  }

  void _armConnectWatchdog(int gen) {
    _connectWatchdog?.cancel();
    _connectWatchdog = Timer(_connectWatchdogTimeout, () {
      if (gen != _connectGen) return;
      if (_sessionState == SessionState.online ||
          _sessionState == SessionState.disconnected) {
        return;
      }
      logger.e(
        'connect: watchdog ${_connectWatchdogTimeout.inSeconds}с — застряли в '
        '${_sessionState.name}, принудительный сброс',
      );
      unawaited(_resetStuckConnect(gen));
    });
  }

  void _cancelConnectWatchdog() {
    _connectWatchdog?.cancel();
    _connectWatchdog = null;
  }

  Future<void> _resetStuckConnect(int gen) async {
    if (gen != _connectGen) return;
    _connectGen++;
    _cancelConnectWatchdog();
    _cleanup();
    _setSessionState(SessionState.disconnected);
    if (_autoReconnect) _scheduleReconnect();
  }

  Future<void> _handleConnectFailure(
    Object error, {
    required String phase,
  }) async {
    logger.e('$phase: $error');
    _cancelConnectWatchdog();
    if (_sessionState != SessionState.disconnected) {
      _cleanup();
      _setSessionState(SessionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Отключается без автореконнекта.
  Future<void> disconnect() async {
    _autoReconnect = false;
    _connectGen++;
    _reconnectTimer?.cancel();
    _cleanup();
    _setSessionState(SessionState.disconnected);
  }

  void wakeUp() {
    if (!_autoReconnect) return;
    switch (_sessionState) {
      case SessionState.disconnected:
        _reconnectAttempts = 0;
        _reconnectTimer?.cancel();
        unawaited(connect());
      case SessionState.connecting:
      case SessionState.connected:
        _reconnectAttempts = 0;
      case SessionState.online:
        unawaited(_probeLiveness());
    }
  }

  /// Отправляет запрос и ждёт ответ от сервера.
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload,
  ) async {
    final session = _session;
    if (session == null) {
      throw StateError('Нет соединения (${Opcode.name(opcode)})');
    }

    final KolibriResponse resp = await session
        .requestMapFull(opcode, _stringKeyed(payload))
        .timeout(
          ServerConfig.requestTimeout,
          onTimeout: () =>
              throw TimeoutException('${Opcode.name(opcode)} таймаут'),
        );

    final packet = Packet(
      cmd: resp.cmd,
      opcode: resp.opcode,
      payload: resp.payload,
    );

    if (packet.isError) {
      if (isSessionExpiredPayload(packet.payload)) {
        final ex = SessionExpiredException(
          messageFromErrorPayload(packet.payload),
        );
        _sessionExpiredController.add(ex);
        throw ex;
      }
      final text = _serverErrorText(packet.payload);
      if (text != null) _errorController.add(text);
      throw PacketError(
        messageFromErrorPayload(packet.payload),
        errorKey: resp.errorKey,
      );
    }
    return packet;
  }

  Future<Map<dynamic, dynamic>?> sendRequestMap(
    int opcode,
    Map<dynamic, dynamic> payload,
  ) async {
    final response = await sendRequest(opcode, payload);
    if (!response.isOk || response.payload is! Map) return null;
    return response.payload as Map<dynamic, dynamic>;
  }

  Future<bool> sendRequestOk(int opcode, Map<dynamic, dynamic> payload) async {
    final response = await sendRequest(opcode, payload);
    return response.isOk;
  }

  Future<Packet> sendRequestOrThrow(
    int opcode,
    Map<dynamic, dynamic> payload,
  ) async {
    final response = await sendRequest(opcode, payload);
    throwIfPacketError(response);
    return response;
  }

  /// Вешает обработчик на пуши с указанным опкодом.
  void registerPushHandler(int opcode, void Function(Packet) handler) {
    _dispatcher.registerHandler(opcode, handler);
  }

  /// Снимает обработчик пушей с указанного опкода.
  void unregisterPushHandler(int opcode) {
    _dispatcher.unregisterHandler(opcode);
  }

  /// Стрим всех входящих пушей от сервера.
  Stream<Packet> get pushStream => _dispatcher.pushStream;

  Future<void> dispose() async {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _cleanup();
    _dispatcher.dispose();
    await _stateController.close();
    await _sessionExpiredController.close();
    await _handshakeSuccessController.close();
    await _errorController.close();
  }

  // Внутрянка

  Future<(KolibriSession, Stream<WireLogEvent>)> _openSession(
    ({String host, int port}) endpoint,
  ) async {
    final deviceInfo = DeviceInfoPlugin();

    String deviceType = 'ANDROID';
    String osVersion = '';
    String deviceName = 'Unknown';
    String architecture = SpoofingService.defaultArchitecture;
    String appVersion = SpoofingService.hardcodedAppVersion;
    int buildNumber = SpoofingService.hardcodedBuildNumber;
    String screen = '420dpi 420dpi 1080x2340';

    if (!_tzInitialized) {
      tz.initializeTimeZones();
      _tzInitialized = true;
    }
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    String timezone = timeZoneName.identifier;
    String locale = 'ru';
    String deviceLocale = Platform.localeName.substring(0, 2);
    String deviceId = await DeviceIdentity.deviceId();
    String pushDeviceType = 'GCM';
    String instanceId = await DeviceIdentity.instanceId();
    int clientSessionId = DeviceIdentity.clientSessionId;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      osVersion = 'Android ${androidInfo.version.release}';
      deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      architecture = androidInfo.supportedAbis.first;
    }

    final spoofed = await SpoofingService.getSpoofedSessionData(
      scope: spoofScope,
    );
    if (spoofed != null) {
      final sDeviceType = spoofed['device_type'] as String?;
      if (sDeviceType != null && sDeviceType != 'IOS') deviceType = sDeviceType;
      final sDeviceName = spoofed['device_name'] as String?;
      if (sDeviceName != null && sDeviceName.isNotEmpty) {
        deviceName = sDeviceName;
      }
      final sOsVersion = spoofed['os_version'] as String?;
      if (sOsVersion != null && sOsVersion.isNotEmpty) osVersion = sOsVersion;
      final sScreen = spoofed['screen'] as String?;
      if (sScreen != null && sScreen.isNotEmpty) screen = sScreen;
      final sTimezone = spoofed['timezone'] as String?;
      if (sTimezone != null && sTimezone.isNotEmpty) timezone = sTimezone;
      final sLocale = spoofed['locale'] as String?;
      if (sLocale != null && sLocale.isNotEmpty) {
        locale = sLocale;
        deviceLocale = sLocale.split(RegExp(r'[-_]')).first;
      }
      final sDeviceLocale = spoofed['device_locale'] as String?;
      if (sDeviceLocale != null && sDeviceLocale.isNotEmpty) {
        deviceLocale = sDeviceLocale;
      }
      final sDeviceId = spoofed['device_id'] as String?;
      if (sDeviceId != null && sDeviceId.isNotEmpty) deviceId = sDeviceId;
      appVersion = (spoofed['app_version'] as String?) ?? appVersion;
      architecture = (spoofed['arch'] as String?) ?? architecture;
      final sBuild = spoofed['build_number'];
      if (sBuild is int) {
        buildNumber = sBuild;
      } else if (sBuild is String) {
        buildNumber = int.tryParse(sBuild) ?? buildNumber;
      }
      final sPushType = spoofed['push_device_type'] as String?;
      if (sPushType != null && sPushType.isNotEmpty) pushDeviceType = sPushType;
      final sInstanceId = spoofed['instance_id'] as String?;
      if (sInstanceId != null && sInstanceId.isNotEmpty) {
        instanceId = sInstanceId;
      }
      final sClientSession = spoofed['client_session_id'];
      if (sClientSession is int) clientSessionId = sClientSession;
    }

    if (!_willAuthenticate) {
      appVersion = SpoofingService.preLoginAppVersion;
      buildNumber = SpoofingService.preLoginBuildNumber;
    }

    _userAgent = {
      'deviceType': deviceType,
      'appVersion': appVersion,
      'osVersion': osVersion,
      'timezone': timezone,
      'screen': screen,
      'pushDeviceType': pushDeviceType,
      'arch': architecture,
      'locale': locale,
      'buildNumber': buildNumber,
      'deviceName': deviceName,
      'deviceLocale': deviceLocale,
    };
    _deviceId = deviceId;
    _architecture = architecture;

    return openSessionWithWireLog(
      host: endpoint.host,
      port: endpoint.port,
      deviceId: deviceId,
      instanceId: instanceId,
      appVersion: appVersion,
      buildNumber: buildNumber,
      deviceType: deviceType,
      osVersion: osVersion,
      timezone: timezone,
      screen: screen,
      pushDeviceType: pushDeviceType,
      arch: architecture,
      locale: locale,
      deviceName: deviceName,
      deviceLocale: deviceLocale,
      clientSessionId: clientSessionId,
      pingIntervalSecs: ServerConfig.pingInterval.inSeconds,
      pingInteractive: !KometSettings.ghostMode.value,
      autoReconnect: false,
      proxy: await _buildProxyUrl(),
    );
  }

  static Future<String?> _buildProxyUrl() async {
    final ProxySettings p;
    try {
      p = await ProxyConfig.load();
    } catch (e) {
      logger.w('connect: ProxyConfig.load упал ($e) — без прокси');
      return null;
    }
    if (!p.isEnabled) return null;
    final scheme = p.type == ProxyType.socks5 ? 'socks5h' : 'http';
    final auth = p.hasCredentials
        ? '${Uri.encodeComponent(p.username!)}:'
              '${Uri.encodeComponent(p.password!)}@'
        : '';
    return '$scheme://$auth${p.host}:${p.port}';
  }

  static Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> payload) =>
      payload.map((k, v) => MapEntry(k is int ? '\$int:$k' : '$k', v));

  void _onPush((int, Map<String, dynamic>) event) {
    _dispatcher.dispatch(
      Packet(cmd: CmdType.push, opcode: event.$1, payload: event.$2),
    );
  }

  void _onWireLog(WireLogEvent e) {
    final payload = _decodeWireJson(e.json);
    if (e.direction == 'out') {
      DebugSessionLog.instance.recordRequest(e.opcode, e.seq, payload);
      TrafficMonitor.instance.recordOutgoing(e.opcode, payload, e.seq, 0);
      return;
    }
    final cmd = _wireCmdCode(e.cmd);
    if (e.cmd != 'push') {
      DebugSessionLog.instance.recordResponse(e.seq, cmd, payload);
    }
    TrafficMonitor.instance.recordIncoming(
      Packet(cmd: cmd, seq: e.seq, opcode: e.opcode, payload: payload),
      0,
    );
  }

  static int _wireCmdCode(String cmd) => switch (cmd) {
    'ok' => CmdType.ok,
    'not_found' => CmdType.notFound,
    'error' => CmdType.error,
    _ => CmdType.request,
  };

  static dynamic _decodeWireJson(String json) {
    try {
      return jsonDecode(json);
    } catch (_) {
      return json;
    }
  }

  void _setSessionState(SessionState state) {
    if (_sessionState == state) return;
    _sessionState = state;
    _stateController.add(state);
    logger.i('Сессия: ${state.name}');
  }

  void _onDisconnected() {
    _connectGen++;
    _cleanup();
    _setSessionState(SessionState.disconnected);
    if (_autoReconnect) _scheduleReconnect();
  }

  Future<void> _probeLiveness() async {
    if (_sessionState != SessionState.online) return;
    final session = _session;
    if (session == null) return;
    final epoch = _sessionEpoch;
    try {
      await session
          .requestMapFull(Opcode.ping, {
            'interactive': !KometSettings.ghostMode.value,
          })
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      if (_sessionEpoch != epoch || _sessionState != SessionState.online) {
        return;
      }
      logger.w('Пробный пинг не прошёл — принудительный реконнект');
      _forceReconnect();
    }
  }

  void _forceReconnect() {
    _connectGen++;
    _cleanup();
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _setSessionState(SessionState.disconnected);
    if (_autoReconnect) unawaited(connect());
  }

  void _cleanup() {
    _cancelConnectWatchdog();
    _livenessTimer?.cancel();
    _livenessTimer = null;
    _pushSub?.cancel();
    _pushSub = null;
    _wireLogSub?.cancel();
    _wireLogSub = null;
    _lastInteractive = null;
    final session = _session;
    _session = null;
    if (session != null) _releaseSession(session);
    _handshakeSuccessController.add('disconnected');
  }

  /// Рвёт соединение и сразу освобождает Rust-объект: иначе tokio-рантайм
  /// сессии живёт до сборки мусора Dart, а в фоне она может не случиться часами.
  static void _releaseSession(KolibriSession session) {
    if (session.isDisposed) return;
    try {
      session.disconnect();
    } catch (_) {}
    try {
      session.dispose();
    } catch (_) {}
  }

  Future<void> reconnectAndLogin() async {
    await connect();
  }

  Future<void> reconnectForLogin() async {
    _suppressReconnectLogin = true;
    try {
      await disconnect();
      await connect(authenticated: true);
    } finally {
      _suppressReconnectLogin = false;
    }
  }

  Future<void> Function()? _onReconnectCallback;

  void setReconnectCallback(Future<void> Function() callback) {
    _onReconnectCallback = callback;
  }

  /// Ядро не отдаёт стрим состояний: раз в [_livenessInterval] опрашиваем его
  /// на разрыв и синхроним interactive-флаг пинга с режимом невидимки.
  void _startLiveness() {
    _livenessTimer?.cancel();
    _lastInteractive = !KometSettings.ghostMode.value;
    _markPresence(_lastInteractive!);
    _livenessTimer = Timer.periodic(_livenessInterval, (_) => _tickLiveness());
  }

  void _tickLiveness() {
    final session = _session;
    if (session == null || _sessionState != SessionState.online) return;
    final st = session.state();
    if (st != 'online' && st != 'connected') {
      logger.w('kolibri сессия "$st" — реконнект');
      _onDisconnected();
      return;
    }
    final interactive = !KometSettings.ghostMode.value;
    if (interactive != _lastInteractive) sendPing(interactive: interactive);
  }

  void sendPing({required bool interactive}) {
    final session = _session;
    if (session == null || _sessionState != SessionState.online) return;
    try {
      session.setPingInteractive(interactive: interactive);
    } catch (_) {}
    _lastInteractive = interactive;
    _markPresence(interactive);
  }

  static void _markPresence(bool interactive) {
    if (interactive) {
      SelfPresence.markOnline();
    } else {
      SelfPresence.markOfflineFromPing();
    }
  }

  static String? _serverErrorText(dynamic payload) {
    if (payload is! Map) return null;
    if (isSessionExpiredPayload(payload)) return null;
    for (final key in ['localizedMessage', 'title']) {
      final v = payload[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static List<CountryName>? _parseRegistrationCountries(dynamic payload) {
    if (payload is! Map) return null;
    final raw = payload['reg-country-code'];
    if (raw is! List || raw.isEmpty) return null;
    final codes = <String>[];
    for (final e in raw) {
      if (e is String && e.isNotEmpty) codes.add(e.toUpperCase());
    }
    if (codes.isEmpty) return null;
    var list = countriesInServerOrder(codes);
    if (list.isEmpty) return null;

    final loc = payload['location'];
    if (loc is String && loc.length == 2) {
      final home = countriesByCode[loc.toUpperCase()];
      if (home != null && !list.any((c) => c.code == home.code)) {
        list = [home, ...list];
      }
    }
    return list;
  }

  void _scheduleReconnect() {
    final delaySec = (2 * (1 << _reconnectAttempts.clamp(0, 3))).clamp(2, 15);
    _reconnectAttempts++;
    logger.i('Реконнект через $delaySecс (попытка $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }
}
