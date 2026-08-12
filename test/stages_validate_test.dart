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
}
