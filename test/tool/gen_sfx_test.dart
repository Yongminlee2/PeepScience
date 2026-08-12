// tool/gen_sfx.dart(순수 Dart wav 합성기) 검증. 두 층:
//  1) 순수 함수 자체 - wav() 헤더/데이터가 올바른지 (파일 I/O 없음)
//  2) 실제로 커밋된 assets/audio/*.wav가 지금 생성기가 만드는 바이트와
//     똑같은지 (브리핑 Step 2 "7개 파일이 assets/audio에 존재" 그대로) -
//     `dart run tool/gen_sfx.dart`를 먼저 돌려 파일을 만들어 둬야 통과한다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/gen_sfx.dart';

const _expectedNames = [
  'tap',
  'place',
  'pop',
  'boing',
  'win',
  'gearTick',
  'buttonClick',
];

void main() {
  test('allSounds()는 Sfx 7종 이름을 정확히 갖는다', () {
    expect(allSounds().keys.toSet(), _expectedNames.toSet());
  });

  test('각 소리는 샘플이 비어있지 않다', () {
    for (final entry in allSounds().entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key}: no samples');
    }
  });

  test('wav()가 올바른 RIFF/WAVE 헤더 + 0이 아닌 데이터를 만든다', () {
    for (final entry in allSounds().entries) {
      final bytes = Uint8List.fromList(wav(entry.value));
      final bd = ByteData.sublistView(bytes);
      String tag(int offset) => String.fromCharCodes(bytes, offset, offset + 4);

      expect(tag(0), 'RIFF', reason: '${entry.key}: RIFF magic');
      expect(tag(8), 'WAVE', reason: '${entry.key}: WAVE format');
      expect(tag(12), 'fmt ', reason: '${entry.key}: fmt chunk id');
      expect(bd.getUint16(20, Endian.little), 1,
          reason: '${entry.key}: PCM format code');
      expect(bd.getUint16(22, Endian.little), 1,
          reason: '${entry.key}: mono channel count');
      expect(bd.getUint32(24, Endian.little), sampleRate,
          reason: '${entry.key}: sample rate');
      expect(bd.getUint16(34, Endian.little), 16,
          reason: '${entry.key}: 16-bit samples');
      expect(tag(36), 'data', reason: '${entry.key}: data chunk id');

      final dataSize = bd.getUint32(40, Endian.little);
      expect(dataSize, greaterThan(0), reason: '${entry.key}: nonzero data');
      expect(dataSize, entry.value.length * 2,
          reason: '${entry.key}: data size matches sample count (16-bit)');
      expect(bytes.length, 44 + dataSize,
          reason: '${entry.key}: total length == header(44) + data');
    }
  });

  test('assets/audio에 7개 wav 파일이 실제로 존재하고 지금 생성기와 바이트가 같다', () {
    final sounds = allSounds();
    for (final name in _expectedNames) {
      final f = File('assets/audio/$name.wav');
      expect(f.existsSync(), isTrue,
          reason:
              '$name.wav가 assets/audio에 없다 - dart run tool/gen_sfx.dart를 먼저 실행');
      expect(
        f.readAsBytesSync(),
        equals(wav(sounds[name]!)),
        reason: '$name.wav가 커밋된 상태와 생성기 출력이 다르다 - 재생성 필요',
      );
    }
  });
}
