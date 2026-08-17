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

  group('rule (f): 프리셋이 트레이 바 뒤에 가려지면 안 된다(편집 화면 기준)', () {
    final report = validateAllStages('test/fixtures/stages_hidden_preset');

    test('완전히 가려진 버튼(y=8.0)은 물리 시뮬레이션 없이 즉시 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s01');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('hidden behind tray'));
      expect(s.failReason, contains('button'));
      // rule (e)와 동일하게 물리를 아예 돌리지 않았다는 근거.
      expect(s.stepsToClear, isNull);
      expect(s.jitterStepsToClear, isEmpty);
    });

    test('걷는 면(윗면)이 가려진 플랫폼(y=7.7)도 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s02');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('hidden behind tray'));
      expect(s.failReason, contains('platform'));
    });

    test('버튼을 보이는 위치(y=5.0)로 옮기면 가림 사유로는 실패하지 않는다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s03');
      expect(s.failReason, isNot(contains('hidden behind tray')));
    });
  });

  // 실기기 검수에서 나온 계열 결함: 규칙 (f)는 아래 트레이 바만 봤고,
  // 위쪽 안내 리본·목표 배지·실행 버튼과 화면 밖은 아무도 검사하지 않아
  // 시작 공이 리본 뒤에 100% 숨은 판과 압정이 화면 위 바깥에 있는 판이
  // 물리 검증을 전부 통과한 채 배포 직전까지 살아 있었다.
  group('rule (g): HUD 뒤나 화면 밖에 숨은 물체가 있으면 안 된다', () {
    final report = validateAllStages('test/fixtures/stages_hud_occluded');

    test('연쇄 리본 뒤에 완전히 숨은 시작 공은 물리 없이 즉시 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s01');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('chain ribbon'));
      expect(s.failReason, contains('rubber_ball'));
      expect(s.stepsToClear, isNull);
      expect(s.jitterStepsToClear, isEmpty);
    });

    test('화면 위 바깥(y=-0.5)에 놓인 압정은 실패한다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s02');
      expect(s.ok, isFalse);
      expect(s.failReason, contains('off canvas'));
      expect(s.failReason, contains('tack'));
    });

    test('같은 판이라도 공을 리본 아래(y=2.0)로 내리면 가림 사유가 사라진다', () {
      final s = report.stages.firstWhere((s) => s.id == 'w1_s03');
      expect(s.failReason, isNot(contains('buried under')));
      expect(s.failReason, isNot(contains('off canvas')));
    });
  });
}
