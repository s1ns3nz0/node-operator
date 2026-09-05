# Node Operator 운영 handoff

기준 커밋은 `e5d4a21`이며, 이 문서는 2026-09-05까지 기록된 검증 결과를
인수인계하기 위한 문서다. 아래의 “마지막 기록 상태”는 새 라이브 조회가 아니라
기존의 비민감성 증거와 병합된 변경을 요약한 것이다. 재개 전에 반드시 `상태 확인`
절차를 다시 수행한다.

## 운영 원칙과 경계

- EKS API, Argo CD, Vault는 사설 경로에서만 운영한다. 로컬에서 접근할 때는 필요
  시간에만 임시 SSM 터널 호스트를 생성한다.
- 비밀값, Vault 토큰, 복구 자료, validator private key, withdrawal credential,
  kubeconfig 및 원시 로그를 Git·Terraform state·CI 증거·handoff에 넣지 않는다.
- Terraform은 클라우드와 비밀이 아닌 identity 경계를, Vault는 런타임 비밀과
  복구 자료를 소유한다. GitHub Actions와 일반 CI는 Vault 내부 endpoint에 직접
  접근하지 않는다.
- `GITHUB_TOKEN` 환경 변수는 덮어쓰지 않는다. 원격 GitHub 상태 확인에 GitHub CLI를
  쓸 때는 필요하면 `env -u GITHUB_TOKEN gh ...`처럼 현재 변수만 제거한다.

## 현재까지 구현된 상태

| 영역 | 마지막 기록 상태 | 운영 의미 |
| --- | --- | --- |
| EKS | 서울 리전의 private-only `node-operator` 클러스터, 암호화 저장소·감사·Pod Identity 기반을 적용했다. | 외부 인터넷에서 Kubernetes API에 직접 접근할 수 없다. |
| 시스템 풀 | `node-operator-managed`는 최소/희망 1로 유지한다. | Argo CD와 플랫폼 add-on을 항상 실행해 빠른 재개를 가능하게 한다. |
| Hoodi 풀 | `node-operator-consensus`, `node-operator-execution`은 최소/희망 0, 최대 1로 운영하도록 구성했고 마지막 비용 절감 시점에 0으로 내렸다. | 클라이언트 실행 때만 EC2 비용이 발생한다. |
| Argo CD | 사설 ECR OCI chart를 사용하는 `node-operator-client` Application이 revision `0.1.6`에서 `Synced`·`Healthy`였고, ECR 인증 갱신 CronJob과 전용 Pod Identity를 적용했다. | Argo CD는 시스템 풀에서 상시 실행되며 ECR 자격증명은 약 6시간마다 갱신된다. |
| 네트워크 | EKS VPC CNI NetworkPolicy enforcement가 `ACTIVE`까지 확인됐다. | 검토된 Kubernetes NetworkPolicy가 런타임에서도 적용된다. |
| Vault | Vault의 AWS auth, Transit 엔진, release signer 정책과 키 경계가 운영자 절차로 구성됐다. 비용 절감 단계에서는 Vault workload를 내리고 PVC를 보존한 상태로 기록됐다. | Vault를 재가동하거나 상태를 점검할 때에도 토큰·키·복구 자료를 읽거나 출력하지 않는다. |
| validator 계약 | UC-2~UC-5의 namespace, ServiceAccount, NetworkPolicy, fencing Lease/RBAC, signer 경계와 Vault 정책 템플릿을 구현·정적 검증했다. | 실제 validator key나 remote signer image는 아직 배포하지 않았다. |
| Hoodi client chart | Nethermind/Prysm StatefulSet, PVC, 내부 Engine API 연결, NetworkPolicy를 chart에 구현했지만 `clients.enabled: false`로 게시했다. | 현재 StatefulSet은 의도적으로 존재하지 않으며 worker pool을 올려도 client가 자동 시작되지 않는다. |

Argo CD의 실제 Application manifest는
`deploy/argocd/node-operator-client-application.yaml`에 있고, 기본 운영 chart 값은
별도 private GitOps 저장소에 있다. chart 버전은 immutable하게 올리고 Argo
Application의 `targetRevision`도 별도 검토 변경으로 올린다.

## 아직 끝나지 않은 과업

우선순위는 다음 순서다.

1. **Engine-JWT custody 준비**: Vault 책임자가 Kubernetes `node-operator`
   namespace에 `engine-api-jwt` Secret을 안전한 외부 절차로 전달한다. workload가
   기대하는 데이터 key는 `jwt`다. 값·내용·토큰은 CI나 이 문서에서 확인하지 않는다.
2. **client chart 활성화 및 GitOps 배포**: private GitOps 저장소에서
   `clients.enabled: true`인 새 immutable chart revision을 검토·게시하고, 이 저장소의
   Argo Application을 그 revision으로 승격한다. Argo가 Sync/Healthy가 될 때까지
   확인한다. 이 단계가 끝나기 전에는 `hoodi-session.sh start`가 의도적으로 실패한다.
3. **UC-1 라이브 proof**: 두 Hoodi pool을 올리고 Nethermind와 Prysm StatefulSet을
   준비 상태까지 검증한다. 동기화·피어·PVC·내부 execution 연결·허용된 NetworkPolicy
   경로를 비민감성 상태 정보로 확인한 후 다시 scale down한다.
4. **UC-2~UC-5 실제 운영 준비**: 검토된 remote signer 이미지를 별도 선정하고,
   validator signing key/keystore/password, withdrawal credential, slashing history,
   backup 및 incident-recovery custody 절차를 승인한다. 이 자산들은 Transit release
   signing key와 분리하며 일반 client Pod나 CI에 제공하지 않는다.
5. **운영 보강**: Vault seal/audit/Raft/PVC 백업의 정기 점검과 복구 훈련, Argo
   Application/ECR refresher 경보, client 동기화·디스크·재시작·NetworkPolicy 거부
   관측 및 알림 소유자를 확정한다.
6. **최종 증거와 독립 검토**: UC-1 proof 후 비민감성 evidence를 갱신하고, validator
   실구현 범위가 승인되면 해당 task별 clean-room debrief를 수행한다.

## 재개 전 상태 확인

사설 EKS 접근이 이미 구성된 터미널에서 아래 명령을 실행한다. 이 명령들은 Secret
값을 읽지 않는다.

```bash
scripts/ops/hoodi-session.sh status
kubectl get application -n argocd node-operator-client
kubectl get cronjob -n argocd argocd-ecr-oci-credentials
```

로컬에 사설 EKS 경로가 없다면 임시 SSM operations host를 먼저 Terraform으로
생성한다. Terraform apply role의 external ID 및 기존 보존 변수는 조직의 승인된 실행
환경에서 제공해야 한다. 임시 호스트 ID, AWS credential, 세션 ID를 문서나 PR에
기록하지 않는다.

생성 뒤에는 다음의 비밀 비포함 절차로 port forwarding을 연다. 첫 번째 터미널에서
실행하고 세션을 계속 열어 둔다. 실제 값은 승인된 실행 환경에서만 얻으며, 복사해
증거에 남기지 않는다.

```bash
INSTANCE_ID="$(terraform -chdir=infra/terraform output -raw temporary_ssm_ops_host_instance_id)"
EKS_HOST="$(aws eks describe-cluster --name node-operator --region ap-northeast-2 \
  --query 'cluster.endpoint' --output text | sed 's#^https://##')"

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${EKS_HOST}\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"8443\"]}" \
  --region ap-northeast-2
```

두 번째 터미널에서는 평소 kubeconfig를 바꾸지 말고 일회성 kubeconfig를 만든다.
TLS hostname 검증은 원래 EKS endpoint hostname을 유지하며,
`--insecure-skip-tls-verify`를 사용하지 않는다.

```bash
TEMP_KUBECONFIG="$(mktemp -t node-operator-kubeconfig.XXXXXX)"
aws eks update-kubeconfig --name node-operator --region ap-northeast-2 \
  --kubeconfig "$TEMP_KUBECONFIG"
CLUSTER_CONTEXT="$(kubectl --kubeconfig "$TEMP_KUBECONFIG" config view --minify \
  -o jsonpath='{.clusters[0].name}')"
kubectl --kubeconfig "$TEMP_KUBECONFIG" config set-cluster "$CLUSTER_CONTEXT" \
  --server=https://127.0.0.1:8443 --tls-server-name="$EKS_HOST"
```

그 뒤 이 절의 `kubectl` 명령에는 `--kubeconfig "$TEMP_KUBECONFIG"`를 붙인다. 작업이
끝나면 SSM 세션을 종료하고 임시 kubeconfig 파일을 제거한다. `aws eks
update-kubeconfig` 뒤에는 현재 AWS caller가 EKS access entry에 등록됐는지도 확인한다.
권한 오류는 네트워크 오류와 다르므로 access entry/policy를 별도로 수정하되, 필요한
최소 권한만 일시적으로 부여한다.

## Hoodi client 재개 절차

아래 순서는 비용과 안전성 때문에 바꾸지 않는다.

1. Vault custody 담당자가 `engine-api-jwt` object와 `jwt` key를 안전하게 준비했음을
   값 노출 없이 확인한다.
2. GitOps 담당자가 client-enabled immutable chart revision을 게시하고 Argo
   Application `targetRevision`을 승격한다. Argo Application이 `Synced`와 `Healthy`가
   된 것을 확인한다.
3. 사설 EKS 접근 경로에서 client StatefulSet이 존재하는지 확인한다.

   ```bash
   kubectl -n node-operator get statefulset nethermind-execution prysm-beacon
   ```

4. worker capacity와 StatefulSet을 함께 시작한다.

   ```bash
   scripts/ops/hoodi-session.sh start --yes
   ```

5. Ready 이후에만 동기화 진행, 피어 수, PVC 여유, 재시작 횟수, internal Engine API
   연결, NetworkPolicy 거부를 관찰한다. 실제 validator key를 이 UC-1 proof에 넣지
   않는다.

`start`는 먼저 StatefulSet 존재와 `engine-api-jwt` object의 **metadata 이름만**
확인한다. Secret의 `.data`를 조회·decode·출력하지 않는다. 따라서 이 사전 조건이
완료되지 않았거나 chart가 아직 disabled이면 start가 실패하는 것이 정상이다.

## 중지와 비용 절감

정상 종료 시 client를 먼저 0으로 내린 뒤 consensus/execution pool을 0으로 내린다.

```bash
scripts/ops/hoodi-session.sh stop --yes
scripts/ops/hoodi-session.sh status
```

이 스크립트는 PVC를 삭제하지 않으며 시스템 pool과 Argo CD도 내리지 않는다. 별도로
만든 임시 SSM host는 작업 창이 끝나면 Terraform의 정상 apply 경로로
`enable_temporary_ssm_ops_host=false`를 설정하여 support resource까지 제거한다. 기존
runbook의 `-target=aws_instance.temporary_ssm_ops_host` destroy는 instance만 급히
정리할 때 쓰는 예외이며, count-controlled IAM/security group/scheduler까지 정리하지
않는다. Vault PVC, release artifact bucket, NAT gateway, EKS control plane은 idle
shutdown의 대상이 아니다. EKS control plane과 시스템 pool, 보존 PVC에는 여전히 비용이
발생한다.

## 주요 파일과 검증 명령

| 목적 | 위치 |
| --- | --- |
| Hoodi start/stop/status | `scripts/ops/hoodi-session.sh` |
| 비용·SSM 운영 runbook | `docs/operations/cost-optimized-hoodi.md` |
| Argo client Application | `deploy/argocd/node-operator-client-application.yaml` |
| ECR OCI 자격증명 refresher | `deploy/argocd/ecr-oci-credentials.yaml` |
| validator 운영 경계 | `docs/operations/validator-key-operations.md` |
| validator 유즈케이스 학습 문서 | `docs/learning/node-operator-use-cases.md` |
| 전체 task evidence | `plans/2026-09-05-always-on-gitops-client/` |

소스 계약 검증은 다음과 같다. 이들은 라이브 리소스를 생성하거나 Secret을 읽지 않는다.

```bash
npm run harness:check
npm run test:hoodi-session-contract
npm run test:argocd-ecr-oci-contract
npm run test:validator-runtime-contract
```

## 확인이 필요한 판단

- `clients.enabled`를 켜는 GitOps 변경은 Engine-JWT custody 준비 후에만 승인한다.
- validator 실제 운영은 remote signer 구현체·key ceremony·slashing database·backup
  복구 연습·incident owner가 정해진 별도 승인 task로 수행한다.
- Vault의 현재 seal/replica 상태, 현재 EKS node group desired size, Argo 상태는 이
  handoff 작성 시점의 새 조회가 아니다. 재개 작업의 첫 단계에서 비민감성 상태 조회로
  다시 검증한다.
