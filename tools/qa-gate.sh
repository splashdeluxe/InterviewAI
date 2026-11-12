#!/bin/zsh
# UI/UX quality gate for InterviewAI. Nils's rule (2026-11-09): this runs
# before every deployment, and a deployment is only reported done when the
# gate passes AND the shots have been reviewed by eye.
#
#   1. grid-lint over Sources (spacing stays on the 4 pt grid)
#   2. snapshot pass: every page and every Settings tab, light and dark,
#      on a seeded test store (tools/snap.sh) - never the real data
#   3. check-layout over every layout JSON the snapshots wrote
#      (grid position, insets, shared edges, no overlaps)
#   4. the shot inventory lands in the results file for the visual review
#
# The real app is quit for the snapshot pass and reopened at the end.
# Results: /Users/nils/qa-gate.results, log: /Users/nils/qa-gate.log,
# status: /Users/nils/qa-gate.status (RUNNING -> DONE)
set -u
exec > /Users/nils/qa-gate.log 2>&1
set -x
echo RUNNING > /Users/nils/qa-gate.status
: > /Users/nils/qa-gate.results
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin
cd /Users/nils/InterviewAI || exit 1
FAIL=0

echo "== 1/3 grid-lint =="
if /bin/zsh tools/grid-lint.sh Sources > /tmp/qa-gridlint.txt 2>&1; then
  echo "GRID-LINT PASS" >> /Users/nils/qa-gate.results
else
  echo "GRID-LINT FAIL" >> /Users/nils/qa-gate.results
  tail -20 /tmp/qa-gridlint.txt
  FAIL=1
fi

echo "== 2/3 snapshots =="
/usr/bin/osascript -e 'tell application "InterviewAI" to quit' 2>/dev/null
sleep 2
/bin/zsh tools/snap.sh > /tmp/qa-snap.txt 2>&1
tail -5 /tmp/qa-snap.txt
SHOTS=$(find /tmp/InterviewAI-shots -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
echo "SHOTS $SHOTS" >> /Users/nils/qa-gate.results
ls /tmp/InterviewAI-shots/ >> /Users/nils/qa-gate.results
[ "$SHOTS" -gt 0 ] || FAIL=1

echo "== 3/3 layout checks =="
JSONS=(/tmp/InterviewAI-shots/*-layout.json(N))
if [ ${#JSONS} -eq 0 ]; then
  echo "no layout files" > /tmp/qa-layout.txt
fi
if [ ${#JSONS} -gt 0 ] && swift tools/check-layout.swift $JSONS > /tmp/qa-layout.txt 2>&1; then
  echo "LAYOUT PASS" >> /Users/nils/qa-gate.results
else
  echo "LAYOUT FAIL" >> /Users/nils/qa-gate.results
  FAIL=1
fi
grep -c "^PASS" /tmp/qa-layout.txt | sed 's/^/LAYOUT-PASS-FILES /' >> /Users/nils/qa-gate.results
grep "^FAIL" /tmp/qa-layout.txt >> /Users/nils/qa-gate.results

open /Users/nils/Applications/InterviewAI.app
[ "$FAIL" -eq 0 ] && echo "QA-GATE PASS" >> /Users/nils/qa-gate.results || echo "QA-GATE FAIL" >> /Users/nils/qa-gate.results
echo DONE > /Users/nils/qa-gate.status
