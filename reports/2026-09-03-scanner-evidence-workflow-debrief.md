# Clean-room debrief — scanner evidence workflow

## 범위 / Scope

이 보고서는 `plans/2026-09-03-scanner-evidence-workflow/`, `.ci/scanners` 및
`.github/workflows`의 관련 변경분, 그리고 이 검토자가 독립 실행한 검증 결과만을
대상으로 한다. 수정을 수행하지 않았고, 이미지 publish·배포·secret 변경도 수행하지
않았다.

## 관찰된 증거 / Observed evidence

- `Dockerfile`은 `run-security-scan.sh`와 세 개의 evidence-collector 의존 스크립트를
  이미지에 복사하고, `/usr/local/bin/run-security-scan`을 `ENTRYPOINT`로 지정한다.
- 엔트리포인트는 정확히 `EVIDENCE_DIRECTORY COMMIT_SHA BASE_SHA` 세 인수를 요구하고,
  읽기 전용 `/workspace`를 대상으로 collector를 실행한다.
- `ci-security.yml`은 workspace를 read-only로, evidence 디렉터리를 writeable로 mount한
  뒤 `--entrypoint bash`로 checked-out runner를 실행하고, `$EVIDENCE_ROOT`만 artifact로
  업로드한다.
- runner는 새 이미지에 packaged collector가 실행 가능하면 `/opt/node-operator-scanner/scripts`를
  사용하고, 그렇지 않으면 checked-out `/workspace/scripts/ci`로 fallback한다.
- scanner-image-release workflow는 scanner 디렉터리뿐 아니라 이미지에 복사되는 세
  `scripts/ci` 파일의 변경에도 실행되며, build context를 repository root로 바꾸었다.
- CI가 참조하는 scanner image digest는 이번 diff에서 바뀌지 않았다. task evidence에는
  변경 전 이미지가 “tools only”이고 scan command는 CI의 inline Docker invocation에서
  제공됐다고 기록돼 있다. 그 기존 invocation도 `bash -lc`를 사용했다.
- 독립 실행 결과:
  - `npm run harness:check`: 통과 (`checked 11 task graph(s)`).
  - `npm run harness:verify`: harness 구조 검사는 통과했으나 `opa`, `conftest`,
    `shellcheck`가 없고 policy fixture 하나도 없어 adapter 검증을 수행하지 못했다.
    `pr-gate`는 `osv produced an incomplete JSON report`를 출력했다.
  - `bash -n .ci/scanners/run-security-scan.sh`: 통과.
  - 최신 compatibility diff의 `git diff --check` 및 runner `bash -n`: 통과.
  - `actionlint`: 환경에 설치되어 있지 않아 workflow lint를 실행하지 못했다.

## 추론 및 검토 판단 / Inference and assessment

- **롤아웃 호환성 이슈 해소 / rollout compatibility resolved by diff:** 이전 보고서의
  우려는 old tools-only digest가 새 ENTRYPOINT를 갖지 않는다는 점이었다. 이제 CI가
  `--entrypoint bash`로 checked-out runner를 직접 실행하므로, old image는 기존 CI가 이미
  사용하던 `bash`와 scanner tools만 제공하면 된다. runner의 fallback도 old image에서
  checked-out collector를 선택한다. 따라서 새 digest를 즉시 promote하지 않아도 entrypoint
  부재 때문에 실행이 막히는 문제는 이 diff 수준에서 해소됐다. 이는 정적 검토에 따른
  판단이며 실제 old digest 실행으로 확인한 결과는 아니다.
- 새 digest를 promote한 뒤에는 동일 runner가 packaged collector를 선택한다. 다만 build,
  publish, immutable digest 갱신 및 해당 이미지의 실제 실행은 이 검토 범위에서 수행·검증되지
  않았다.
- `$EVIDENCE_ROOT` 전체 업로드가 “declared non-sensitive output only”인지 여부는
  collector 구현과 실제 산출물을 이 클린룸 검토에서 읽거나 실행하지 않았으므로
  입증되지 않았다. uploader path 자체는 collector에 전달하는 evidence root와 일치한다.
- `Dockerfile.dockerignore`는 존재하지만 실제 Docker build를 하지 않았으므로, 해당
  build context에서 ignore 규칙이 기대대로 적용되는지는 미검증이다.
- 이전 CI에 있던 `SKIP_TERRAFORM=true` 환경변수는 최신 diff에서 제거됐다. collector의
  환경변수 의미와 실제 실행 결과는 이 제한된 클린룸 범위에서 검토하지 않았으므로, 그 변경의
  안전성·필요성은 판단하지 않았다.
- task bundle의 `graph.json`은 모든 node를 `completed`로 기록한다. `evidence.json`은
  `completed_with_environmental_validation_limits` 상태이며, diff check·runner syntax·YAML
  parse·harness check·packaged script executability 통과와, 누락된 policy 도구/fixture 및
  Docker manifest resolution 때문에 막힌 검증을 함께 기록한다.

## 권고 / Required follow-up

1. old pinned digest와 새 promoted digest 각각에서 실제 image invocation을 검증한다.
2. 새 scanner image를 승인된 release 경로에서 빌드한 뒤 digest를 확인하고,
   promotion 시 `SCANNER_IMAGE`를 그 digest로 갱신한다.
3. 실제 image invocation과 artifact contents를 검증해 evidence root에 비민감 결과만
   생성·업로드되는지 확인한다.
4. `opa`, `conftest`, `shellcheck`, 필요한 policy fixture 및 `actionlint`가 있는
   환경에서 harness adapter와 workflow lint를 재실행하고, 결과를 task evidence에 기록한다.
