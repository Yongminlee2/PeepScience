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
}
