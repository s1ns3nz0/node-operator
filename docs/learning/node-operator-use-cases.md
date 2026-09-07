# 노드 운영자 유즈케이스 학습 문서

이 문서는 Hoodi 노드 운영과 validator 운영을 이해하기 위한 다섯 가지
유즈케이스를 설명한다. 실행 명령이나 비밀값은 포함하지 않는다.

## UC-1. Validator 없이 Hoodi 노드 운영

실행 클라이언트(Nethermind)와 합의 클라이언트(Prysm)를 운영해 블록 동기화,
P2P 연결, 네트워크 상태를 관찰하는 경우다. 이 단계의 노드는 validator가
아니므로 블록 제안이나 attest에 서명하지 않는다.

핵심은 **노드 운영과 validator 운영은 다르다**는 점이다. 일반 노드는
클라이언트 이미지와 네트워크 연결만으로 동작할 수 있으며, validator signing
key나 withdrawal credential이 필요하지 않다. 따라서 먼저 이 유즈케이스로
클라이언트의 동기화, 저장소, 네트워크 정책, 비용 제어를 검증한 뒤 validator
기능으로 넘어가는 편이 안전하다.

## UC-2. Validator 온보딩과 deposit 준비

새 validator를 만들고 네트워크에 참여시키기 전 준비하는 과정이다. 이때는
validator signing key, 암호화된 keystore, keystore password, withdrawal
credential, deposit data가 서로 다른 성격의 자산으로 생긴다.

가장 중요한 원칙은 키 생성과 검증을 실행 중인 Kubernetes workload와 분리하는
것이다. 생성 ceremony에서는 deposit data와 공개키를 독립적으로 검증하고,
나중에 확인할 수 있는 해시·승인 기록만 남긴다. 특히 withdrawal credential은
일상적인 노드 운영에 쓰이지 않으며, validator signing key보다 더 엄격한 별도
보관 대상이다.

## UC-3. Remote signer를 통한 validator 서명

validator가 활성화되면 합의 클라이언트는 proposer duty나 attestation duty에
필요한 서명을 요청한다. 이때 private key를 합의 클라이언트 Pod에 직접 넣지
않고, 별도 remote signer가 키를 사용하도록 분리하는 유즈케이스다.

합의 클라이언트는 “서명을 요청하는 클라이언트”이고, remote signer는 “키를
보유하고 실제 서명을 수행하는 구성요소”다. 두 역할을 분리하면 클라이언트가
침해되어도 키 노출 범위를 줄일 수 있다. signer는 한 validator set에만 제한된
짧은 수명의 workload identity를 사용하고, CI·릴리스 서명·다른 validator set에
접근할 수 없어야 한다.

## UC-4. Slashing 방지와 장애 조치

validator는 같은 duty에 두 번 서명하면 slashing 위험이 있다. Pod 재시작,
노드 장애, 운영자 failover처럼 평범해 보이는 사건도 두 signer가 동시에
활성화되면 심각한 문제가 될 수 있다.

그래서 validator key와 별도로 slashing-protection history를 관리한다. 장애
조치 때는 기존 signer를 먼저 fence하여 더 이상 서명할 수 없게 만들고,
검증된 slashing history를 후보 signer에 import한 뒤에만 새 signer를
활성화한다. 이 유즈케이스의 핵심은 빠른 복구보다 **기존 signer가 확실히
멈췄다는 증명**이다.

## UC-5. 키 교체, 자발적 exit, 침해 대응

signer compromise가 의심되거나 validator 운영을 종료해야 할 때의
유즈케이스다. 이 상황에서는 먼저 signer의 workload identity와 접근 정책을
회수하고, signer를 fence하여 모든 추가 서명을 막는다.

그 다음에야 네트워크 규칙에 맞춰 signing key 교체, 복구 또는 voluntary exit를
수행한다. slashing history와 감사 기록을 지우는 것은 문제를 해결하지 못하므로
보존해야 한다. withdrawal credential은 단순한 애플리케이션 비밀번호처럼
교체하는 대상이 아니며, 별도 승인과 복구 절차가 필요한 최상위 custody
자산이라는 점이 이 유즈케이스의 핵심이다.
