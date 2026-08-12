import 'package:flutter_test/flutter_test.dart';
import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/validate_core.dart';

void main() {
  test('assets/stages 전체가 지터 포함 4회 클리어하고 파일 목록이 stageOrder와 정확히 일치한다', () {
    final report = validateAllStages('assets/stages');

    expect(report.missingFiles, isEmpty,
        reason: 'stageOrder에 있는데 파일이 없음: ${report.missingFiles}');
    expect(report.extraFiles, isEmpty,
        reason: 'stageOrder에 없는 파일이 존재함: ${report.extraFiles}');
    expect(report.stages.map((s) => s.id).toList(), stageOrder);
    for (final s in report.stages) {
      expect(s.ok, isTrue, reason: '${s.id}: ${s.failReason}');
    }
  });

  test('stageOrder에 없는 파일이 섞이면 extraFiles에 잡힌다', () {
    final report = validateAllStages('test/fixtures/stages_extra');
    expect(report.extraFiles, contains('w9_s99'));
  });

  test('stageOrder 파일이 빠지면 missingFiles에 잡힌다', () {
    final report = validateAllStages('test/fixtures/stages_missing');
    expect(report.missingFiles, contains('w1_s03'));
  });

  test('빈 배치로도 클리어되는(self-solving) 스테이지는 실패한다', () {
    final report = validateAllStages('test/fixtures/stages_self_solving');
    final s = report.stages.single;
    expect(s.ok, isFalse);
    expect(s.failReason, contains('self-solving'));
  });

  test('파일명과 내부 id가 다르면(복붙 흔적) 실패한다', () {
    // w1_s01.json 파일 안에 "id": "w1_s02"가 들어있는 복붙 실수 케이스.
    final report = validateAllStages('test/fixtures/stages_id_mismatch');
    final s = report.stages.single;
    expect(s.id, 'w1_s01');
    expect(s.ok, isFalse);
    expect(s.failReason, contains('id'));
  });

  group('rule (e): 정답 배치가 게임 자신의 canPlaceAt 규칙으로도 실제 배치 가능해야 한다', () {
    final report = validateAllStages('test/fixtures/stages_placement_illegal');

    test('경계 밖(x=0.0 < 0.3) solution은 물리 시뮬레이션 없이 즉시 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s01');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('out of bounds'));
      // 물리를 아예 돌리지 않았다는 근거 - 배치 불가한 정답을 1800스텝 굴릴
      // 이유가 없다(더 근본적인 문제부터 보고).
      expect(s.stepsToClear, isNull);
      expect(s.jitterStepsToClear, isEmpty);
    });

    test('트레이 개수보다 solution이 더 많이 쓰면 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s02');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('tray'));
    });
  });
}
