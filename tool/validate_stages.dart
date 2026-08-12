// Headless stage validator: `dart run tool/validate_stages.dart`.
// Prints a per-stage table and exits 1 if anything fails (missing/extra
// file, parse error, or a solution/jitter run that doesn't clear).
import 'dart:io';

import 'package:piyak_science/sim/registry.dart';
import 'package:piyak_science/sim/validate_core.dart';

void main() {
  final report = validateAllStages('assets/stages');

  stdout.writeln('=== PiyakScience Stage Validation (assets/stages) ===');
  var passCount = 0;
  for (final s in report.stages) {
    if (s.ok) {
      passCount++;
      stdout.writeln('${s.id.padRight(10)} PASS  steps=${s.stepsToClear}  '
          'jitter=${s.jitterStepsToClear}');
    } else {
      stdout.writeln('${s.id.padRight(10)} FAIL  ${s.failReason}');
    }
  }

  if (report.missingFiles.isNotEmpty) {
    stdout.writeln('missing files (in stageOrder, no <id>.json): '
        '${report.missingFiles}');
  }
  if (report.extraFiles.isNotEmpty) {
    stdout.writeln('extra files (not in stageOrder): ${report.extraFiles}');
  }

  stdout.writeln('RESULT: $passCount/${stageOrder.length} PASS'
      '${report.ok ? '' : ' - FAILED'}');

  if (!report.ok) exit(1);
}
