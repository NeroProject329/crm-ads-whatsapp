# Decisoes - Etapa 5

PostgreSQL continua sendo a fonte de verdade da fila.

BullMQ nao e necessario para a autoridade do scheduler.

Claim utiliza FOR UPDATE SKIP LOCKED.

Lease permite recovery de workers interrompidos.

Backpressure e global por Employee.

Round-robin e persistido por Traffic Pool.

Ordem do cursor e baseada em TrafficPoolMember.position.

Microbatch representa capacidade reservada, nao lead entregue.

scheduledLeadCount e separado de fulfilledLeadCount.

Queue COMPLETED significa planejamento concluido.

AdsRequest FULFILLED somente sera usado quando leads reais forem entregues.

Defaults:

- ADS_SCHEDULER_INTERVAL_MS=1000
- ADS_MICROBATCH_SIZE=10
- ADS_MAX_INFLIGHT_PER_EMPLOYEE=100
- ADS_CLAIM_LEASE_MS=30000
- ADS_BACKPRESSURE_DELAY_MS=5000
- ADS_MICROBATCH_YIELD_MS=250
- ADS_MAX_CLAIMS_PER_TICK=25
- ADS_MAX_QUEUE_ATTEMPTS=25
