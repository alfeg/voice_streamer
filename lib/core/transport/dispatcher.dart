import 'dart:async';

import '../protocol/packet.dart';
import '../protocol/opcode_map.dart';
import '../utils/log_redact.dart';
import '../utils/logger.dart';

typedef PacketHandler = void Function(Packet packet);

/// Роутер входящих пушей по opcode.
///
/// Ответы на запросы матчит Rust-ядро kolibri, сюда приходят только пуши.
class PacketDispatcher {
  final Map<int, PacketHandler> _pushHandlers = {};

  final _pushController = StreamController<Packet>.broadcast();

  /// Стрим всех входящих пушей.
  Stream<Packet> get pushStream => _pushController.stream;

  /// Вешает обработчик на пуши с конкретным опкодом.
  void registerHandler(int opcode, PacketHandler handler) {
    _pushHandlers[opcode] = handler;
  }

  void unregisterHandler(int opcode) {
    _pushHandlers.remove(opcode);
  }

  void dispatch(Packet packet) {
    final tag = Opcode.name(packet.opcode);
    logger.i(
      '<= push {opcode: ${packet.opcode}, payload: ${payloadForLog(packet.payload)}}',
    );
    final handler = _pushHandlers[packet.opcode];
    if (handler != null) {
      try {
        handler(packet);
      } catch (e) {
        logger.w('$tag handler failed: $e');
      }
    }
    _pushController.add(packet);
  }

  void dispose() {
    _pushController.close();
  }
}
