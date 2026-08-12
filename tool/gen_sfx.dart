// 효과음 7종을 순수 Dart로 합성해 assets/audio/*.wav로 쓴다. Flutter 의존성
// 없음 - `dart run tool/gen_sfx.dart`로 실행한다.
//
// 파일명은 lib/services/sound.dart의 Sfx enum 이름과 정확히 같아야 한다
// (예: gearTick.wav, buttonClick.wav - snake_case가 아니라 enum.name 그대로,
// Sound.play가 'audio/${s.name}.wav'로 찾는다). 이 tool은 순수 Dart 유지를
// 위해 그 enum을 직접 import하지 않는다 - test/tool/gen_sfx_test.dart가
// 이름이 어긋나면 잡아준다.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int sampleRate = 22050;

/// WAV(PCM 16bit mono) 바이트 인코딩 - task-18 브리핑에 주어진 그대로.
List<int> wav(List<double> samples, {int rate = sampleRate}) {
  final data = samples.map((s) => (s.clamp(-1, 1) * 32767).round()).toList();
  final b = BytesBuilder();
  void u32(int v) =>
      b.add([v, v >> 8, v >> 16, v >> 24].map((x) => x & 255).toList());
  void u16(int v) => b.add([v & 255, (v >> 8) & 255]);
  b.add('RIFF'.codeUnits);
  u32(36 + data.length * 2);
  b.add('WAVEfmt '.codeUnits);
  u32(16);
  u16(1);
  u16(1);
  u32(rate);
  u32(rate * 2);
  u16(2);
  u16(16);
  b.add('data'.codeUnits);
  u32(data.length * 2);
  for (final d in data) {
    u16(d & 0xFFFF);
  }
  return b.toBytes();
}

int _n(double ms) => (sampleRate * ms / 1000).round();

/// 지수 감쇠 + 시작/끝 짧은 선형 페이드(비영점에서 뚝 끊기면 나는 클릭음
/// 방지). amp(peak) 자체는 각 소리 쪽에서 0.5 정도로 얌전하게 잡는다.
double _env(int i, int n, {double decay = 6, int fadeSamples = 80}) {
  final t = i / n;
  final decayEnv = exp(-decay * t);
  final fs = min(fadeSamples, n ~/ 2);
  if (fs == 0) return decayEnv;
  final inFade = i < fs ? i / fs : 1.0;
  final tailIndex = n - 1 - i;
  final outFade = tailIndex < fs ? tailIndex / fs : 1.0;
  return decayEnv * inFade * outFade;
}

/// 순간 주파수 함수 [freqAt](t)를 위상 누적으로 적분해 사인파를 만든다 -
/// 스윕/비브라토(place/boing)에서 sin(2*pi*f(t)*t)를 그대로 쓰면 왜곡되는
/// 것을 피하는, 시간 가변 주파수의 정석 처리.
List<double> _tone(int n, double Function(double t) freqAt,
    {double amp = 0.5, double decay = 6}) {
  final out = List<double>.filled(n, 0);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    phase += 2 * pi * freqAt(t) / sampleRate;
    out[i] = sin(phase) * amp * _env(i, n, decay: decay);
  }
  return out;
}

List<double> _noise(int n, {double amp = 0.5, double decay = 9}) {
  final rng = Random(12345); // 고정 시드 - 다시 돌려도 바이트가 똑같다.
  return [
    for (var i = 0; i < n; i++)
      (rng.nextDouble() * 2 - 1) * amp * _env(i, n, decay: decay)
  ];
}

List<double> tapSamples() => _tone(_n(30), (t) => 1000, decay: 8);

List<double> placeSamples() => _tone(
    _n(80), (t) => 500 + (300 - 500) * (t / 0.08).clamp(0.0, 1.0),
    decay: 4);

List<double> popSamples() => _noise(_n(60), decay: 9);

List<double> boingSamples() =>
    _tone(_n(200), (t) => 150 + 35 * sin(2 * pi * 9 * t), decay: 3);

List<double> winSamples() {
  const notes = [523.25, 659.25, 783.99, 1046.50]; // 도 미 솔 도
  final noteN = _n(150);
  return [for (final f in notes) ..._tone(noteN, (t) => f, decay: 6)];
}

List<double> gearTickSamples() => _tone(_n(20), (t) => 900, decay: 10);

List<double> buttonClickSamples() => _tone(_n(40), (t) => 700, decay: 7);

/// 이름 -> 샘플. 키는 Sfx.values의 이름과 정확히 같아야 한다(파일 헤더
/// 주석 참고).
Map<String, List<double>> allSounds() => {
      'tap': tapSamples(),
      'place': placeSamples(),
      'pop': popSamples(),
      'boing': boingSamples(),
      'win': winSamples(),
      'gearTick': gearTickSamples(),
      'buttonClick': buttonClickSamples(),
    };

void main() {
  final dir = Directory('assets/audio');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final sounds = allSounds();
  for (final entry in sounds.entries) {
    File('${dir.path}/${entry.key}.wav').writeAsBytesSync(wav(entry.value));
  }
  // ignore: avoid_print
  print('generated ${sounds.length} sfx wav files in ${dir.path}');
}
