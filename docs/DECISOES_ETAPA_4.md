# Decisoes - Etapa 4

PostgreSQL e a fonte de verdade do estado da fila.
BullMQ podera atuar como mecanismo de execucao na Etapa 5.

Cada AdsRequest possui no maximo um AdsQueueItem.

EMPLOYEE cria pedidos somente para os proprios Sites e Traffic Pools.
employeeId e organizationId nao sao aceitos como autoridade a partir do body.

Queue ordering: priority -> availableAt -> enqueuedAt -> id.

Pedido entra na fila somente quando existe numero elegivel no Traffic Pool.

Etapa 4 permite QUEUED -> CANCELLED e WAITING -> CANCELLED.

requestedLeadCount: minimo 1 e maximo 100000.

Etapa 5 implementara scheduler, claim/lease, microbatches, round-robin, backpressure, overflow, progress, completion e failure.
